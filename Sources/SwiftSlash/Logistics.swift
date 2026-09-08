/*
LICENSE MIT
copyright (c) tanner silva 2026. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_posix_helpers
import __cswiftslash_eventtrigger
import SwiftSlashFHHelpers
import SwiftSlashEventTrigger
import SwiftSlashFIFO
import SwiftSlashFuture
import SwiftSlashGlobalSerialization

/// the result of a waitpid call. this is used to determine how a child process exited. similar to pthread_join but for child processes.
internal enum WaitPIDResult {
	/// the child process was signaled to exit. the associated value is the signal number that caused the child process to exit.
	case signaled(Int32)
	/// the child process exited normally. the associated value is the exit status of the child process.
	case exited(Int32)
	/// the waitpid call failed. the associated value is the errno value set by the failed waitpid call.
	case failed(errno:Int32)
}

extension pid_t {
	/// decodes a raw waitpid status into a WaitPIDResult.
	private func decodeWaitStatus(_ statusCapture:Int32) -> WaitPIDResult {
		if __cswiftslash_eventtrigger_wifsignaled(statusCapture) != 0 {
			return WaitPIDResult.signaled(__cswiftslash_eventtrigger_wtermsig(statusCapture))
		} else if __cswiftslash_eventtrigger_wifexited(statusCapture) != 0 {
			return WaitPIDResult.exited(__cswiftslash_eventtrigger_wexitstatus(statusCapture))
		}
		fatalError("SwiftSlash WaitPID error - unrecognized exit code & status combination. this is a critical and unexpected bug. \(#file):\(#line)")
	}

	/// waits for the child process associated with `self` to be reaped.
	/// reaping is event-driven when possible: the process is registered with the event
	/// trigger (kqueue `EVFILT_PROC` on macOS, a pidfd on Linux), whose dedicated
	/// polling thread signals a FIFO when the process exits. the FIFO wait is
	/// cancellation-immune (`.noAction`), so a cancelled task suspends until the reap
	/// becomes possible instead of busy-spinning, and the child process's own task never
	/// blocks the actor. a cooperative polling loop is retained as a fallback for
	/// platforms without kernel process monitoring (linux kernels older than 5.3).
	internal func waitPIDAsync(on trigger:EventTrigger) async -> WaitPIDResult {
		do {
			let exitFIFO:FIFO<Int, Never> = try! .init()
			let exitConsumer = exitFIFO.makeAsyncConsumer()
			try await ProcessLogistics.registerProcessExitMonitor(self, on:trigger, fifo:exitFIFO)
			// suspend until the process-exit event arrives. this suspension survives
			// task cancellation: the event trigger's polling thread is independent of
			// the calling task.
			_ = await exitConsumer.next(whenTaskCancelled:.noAction)
			await ProcessLogistics.deregisterProcessExitMonitor(self, on:trigger)
			// the process has exited. reap it with a brief drain to cover any residual
			// window between the exit event and waitability.
			var statusCapture:Int32 = 0
			drainLoop: while true {
				switch waitpid(self, &statusCapture, WNOHANG) {
					case -1:
						return WaitPIDResult.failed(errno:__cswiftslash_get_errno())
					case 0:
						try? await Task.sleep(for:.milliseconds(1))
						continue drainLoop
					default:
						return decodeWaitStatus(statusCapture)
				}
			}
		} catch {
			// registration failed (e.g. no pidfd support on an old kernel, or fd
			// exhaustion). the registration's stream entry was already enqueued before
			// the kernel call, so drop it now to keep the trigger's active set clean,
			// then fall back to cooperative polling.
			await ProcessLogistics.dropProcessExitMonitor(self, on:trigger)
			return await waitPIDByPolling()
		}
	}

	/// cooperative poll fallback for reaping. only used when kernel process monitoring
	/// is unavailable. NOTE: on a cancelled task `Task.sleep` throws without suspending,
	/// so this loop tight-spins (bounded by the child's actual exit); this is accepted
	/// only because the fast, kernel-driven path covers all supported modern platforms.
	private func waitPIDByPolling() async -> WaitPIDResult {
		var statusCapture:Int32 = 0
		reapLoop: while true {
			let wpidReturn = waitpid(self, &statusCapture, WNOHANG)
			switch wpidReturn {
				case -1:
					let errNo = __cswiftslash_get_errno()
					guard errNo == EINTR else {
						return WaitPIDResult.failed(errno:errNo)
					}
					continue reapLoop
				case 0:
					// child is still running. yield to the actor, then poll again.
					// the sleep is best-effort: cancellation must not abort the reap.
					try? await Task.sleep(for:.milliseconds(10))
					continue reapLoop
				default:
					return decodeWaitStatus(statusCapture)
			}
		}
	}
}

internal struct ProcessLogistics {

	/// encompasses all of the variables that must be present to launch a child process.
	internal struct LaunchPackage:Sendable {
		/// represents the path to the executable that will be launched.
		internal let exe:Path
		/// represents the arguments that will be passed to the child process.
		internal let arguments:[String]
		/// represents the working directory of the child process when it is launched.
		internal let workingDirectory:Path
		/// represents the environment variables that will be assigned to the child process.
		internal let env:[String:String]
		/// represents a mapping of the data channels with the file handles of the child process.
		internal let dataChannels:[Int32:DataChannel]

		internal init(
			exe exePath:consuming Path,
			arguments argsIn:consuming [String],
			workingDirectory wd:Path,
			env envIn:[String:String],
			dataChannels io:[Int32:DataChannel]
		) {
			exe = exePath
			arguments = argsIn
			workingDirectory = wd
			env = envIn
			dataChannels = io
		}

		/// expose all of the arguments for this launch package as c pointers that could be used to launch a child process.
		fileprivate borrowing func exposeArguments<R, E>(_ aHandler:(UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws(E) -> R) throws(E) -> R where E:Swift.Error {
			let buildArgs = [exe.path()] + arguments
			// declare the base array for the arguments. the last element of the array is nil.
			let baseArray = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity:buildArgs.count + 1)
			defer {
				baseArray.deallocate()
			}
			// populate the base array with the arguments.
			for (i, arg) in buildArgs.enumerated() {
				baseArray[i] = strndup(arg, arg.count)
			}
			// cap the base array with nil.
			baseArray[buildArgs.count] = nil
			defer {
				for i in 0..<buildArgs.count {
					free(baseArray[i])
				}
			}
			return try aHandler(baseArray)
		}

		/// the configuration for a child process after it has been launched.
		internal struct Launched {
			internal let writeTasks:[WriteTask]
			internal let readTasks:[ReadTask]
			internal let launchedPID:pid_t
			/// the event trigger that services this launch's io and reaping.
			internal let eventTrigger:EventTrigger
			
			internal struct WriteTask {
				internal let terminationFuture:Future<Void, Never>
				internal let userDataStream:DataChannel.ChildRead.ParentWrite
				internal let writeConsumerFIFO:FIFO<Void, Never>
				internal let wFH:Int32
				internal let eventTrigger:EventTrigger
				internal func launch(taskGroup:inout ThrowingTaskGroup<Void, Swift.Error>) {
					terminationFuture.whenResult({ [f = writeConsumerFIFO, uds = userDataStream.fifo] _ in
						try? f.finish()
						try? uds.finish()
					})
					taskGroup.addTask { [writeConsumer = writeConsumerFIFO.makeAsyncConsumerExplicit(), et = eventTrigger] in
						defer {
							try! et.deregister(writer:wFH)
							try! wFH.closeFileHandle()
						}

						// this function will retrieve the next data chunk that the user wants to write.
						func getNextWriteStep(iterator:borrowing FIFO<([UInt8], Future<Void, DataChannel.ChildRead.ParentWrite.Error>?), Never>.AsyncConsumerExplicit) async -> WriteStepper? {
							switch await iterator.next(whenTaskCancelled:.noAction) {
								case .element(let (newUserDataToWrite, writeCompleteFuture)):
									// this is a signal that the file handle is ready for writing.
									return WriteStepper(newUserDataToWrite, writeFuture:writeCompleteFuture)
								case .capped(_):
									// this is a signal that the file handle is not ready for writing.
									return nil
								case .wouldBlock:
									fatalError("SwiftSlashFIFO :: unexpected wouldBlock condition in WriteTask.launch()")
							}
						}

						// this function will attempt to write the entire contents of the current write step to the file handle.
						func flushCurrentStep(_ currentWriteStep:inout WriteStepper?) throws(FileHandleError) {
							switch try currentWriteStep!.write(to:wFH) {
								case .retireMe:
									currentWriteStep = nil
									return
								case .holdMe:
									return
							}
						}

						let userDataConsume = userDataStream.makeAsyncConsumer()

						var currentWriteStepper:WriteStepper? = nil
						// main loop. if this loop is broken, it means that the termination future has been set.
						systemEventLoopInfinite: repeat {
							// wait for the system to indicate that the file handle is ready for writing.
							switch await writeConsumer.next(whenTaskCancelled:.noAction) {
								case .element(_):
									if currentWriteStepper == nil {
										// this is a signal that the file handle is ready for writing.
										currentWriteStepper = await getNextWriteStep(iterator:userDataConsume)
										guard currentWriteStepper != nil else {
											// user is ready for this stream to be closed.
											break systemEventLoopInfinite
										}
									}
									try flushCurrentStep(&currentWriteStepper)
								case .capped(_):
									// this is a signal that the file handle is not ready for writing.
									break systemEventLoopInfinite
								case .wouldBlock:
									fatalError("SwiftSlashFIFO :: unexpected wouldBlock condition in WriteTask.launch()")
							}
						} while true
						// data channel has been terminated. now we need to just cleanup any pending writes that the user might have stored in the FIFO. all futures found in the fifo at this point will be returned with an error instead of a successful completion or cancellation.
						finalFlushLoop: while currentWriteStepper != nil {
							switch await userDataConsume.next(whenTaskCancelled:.noAction) {
								case .element(let (_, writeCompleteFuture)):
									_ = try? writeCompleteFuture?.setFailure(.dataChannelClosed)
								case .capped(_):
									// this is a signal that the file handle is not ready for writing.
									break finalFlushLoop
								case .wouldBlock:
									fatalError("SwiftSlashFIFO :: unexpected wouldBlock condition in WriteTask.launch()")
							}
						}
					}
				}
			}
			internal struct ReadTask {
				internal let terminationFuture:Future<Void, Never>
				internal let separator:[UInt8]
				internal let userDataStream:DataChannel.ChildWrite.ParentRead
				internal let systemReadEventsFIFO:FIFO<Int, Never>
				internal let rFH:Int32
				internal let eventTrigger:EventTrigger
				internal func launch(taskGroup:inout ThrowingTaskGroup<Void, Swift.Error>) {
					terminationFuture.whenResult({ [f = systemReadEventsFIFO] _ in
						try? f.finish()
					})

					taskGroup.addTask { [systemReadEvents = systemReadEventsFIFO.makeAsyncConsumer(), et = eventTrigger] in
						// this is the line parsing mechanism that allows us to separate arbitrary data into lines of a given specifier.
						var lineParser = LineParser(separator:separator, nasync:userDataStream.fifo)
						defer {
							// this is the only place where action happens with the file handle,
							try! et.deregister(reader:rFH)
							try! rFH.closeFileHandle()
							lineParser.finish()
						}
						// wait for the system to indicate that the file handle is ready for reading.
						var largestReadSize = 256
						readLoop: while let readableSize = await systemReadEvents.next(whenTaskCancelled:.finish(.success(()))) {
							do {
								if readableSize > largestReadSize {
									largestReadSize = readableSize
								}
								// prepare the lineparser to intake the data.
								_ = try lineParser.intake(bytes:readableSize) { wptr in
									// read the data directly from the handle to the lineparser.
									return try rFH.readFH(into:wptr.baseAddress!, size:readableSize)
								}
							} catch FileHandleError.error_wouldblock {
								continue readLoop
							}
						}
						do {
							// prepare the lineparser to intake the data.
							var writtenCount:Int
							repeat {
								writtenCount = try lineParser.intake(bytes:largestReadSize) { wptr in
									// read the data directly from the handle to the lineparser.
									return try rFH.readFH(into:wptr.baseAddress!, size:largestReadSize)
								}
							} while writtenCount > 0
						} catch FileHandleError.error_wouldblock {
							// no action
						} catch let error {
							throw error
						}
					}
				}
			}
		}
	}
	
	/// one of two types of pipese that are used to facilitate the IO exchange between the parent and child process.
	fileprivate enum Pipe {
		/// the pipe that the parent process will read from as the child process writes to it.
		case readPipe(PosixPipe)
		/// the pipe that the child process will read from as the parent process writes to it.
		case writePipe(PosixPipe)
	}

	/// the event trigger that will be used to facilitate the IO exchange between the parent and child process.
	@SwiftSlashGlobalSerialization fileprivate static var eventTrigger:EventTrigger? = nil

	/// registers a process exit monitor with the event trigger. serialized because the trigger's registration stream is shared across launches.
	@SwiftSlashGlobalSerialization internal static func registerProcessExitMonitor(_ pid:pid_t, on trigger:EventTrigger, fifo:consuming FIFO<Int, Never>) throws {
		try trigger.register(process:pid, fifo)
	}

	/// deregisters a process exit monitor with the event trigger. errors are intentionally swallowed: this is best-effort cleanup at the end of a reap.
	@SwiftSlashGlobalSerialization internal static func deregisterProcessExitMonitor(_ pid:pid_t, on trigger:EventTrigger) {
		try? trigger.deregister(process:pid)
	}

	/// drops a process exit registration from the event trigger's registration stream
	/// without a kernel call. used when a registration failed after its stream entry was
	/// enqueued, so no stale `.process` entry can linger in the trigger's active set.
	@SwiftSlashGlobalSerialization internal static func dropProcessExitMonitor(_ pid:pid_t, on trigger:EventTrigger) {
		trigger.dropProcessRegistration(pid)
	}

	@SwiftSlashGlobalSerialization internal static func launch(package:borrowing LaunchPackage) throws -> LaunchPackage.Launched {
		// the event trigger is required for every launch: it services the built-in
		// channel readiness signals AND the process-exit monitor that drives the
		// cooperative reaping of the child process.
		if eventTrigger == nil {
			eventTrigger = try EventTrigger()
		}

		// caller-provided ("bring your own") descriptors that must be bound to child
		// file handles at spawn time. these descriptors are not owned by swiftslash:
		// it will never close, mutate, register, read, or write them. keeping them in
		// a separate dictionary from the swiftslash-owned pipes makes it structurally
		// impossible for any pipe cleanup path to touch them.
		var byoFdBindings:[Int32:Int32] = [:]
		// private copies (dup) of the caller's descriptors, taken at validation time.
		// using the copy as the dup2 source closes the window between validation and
		// spawn: if the caller closes their descriptor after validation, the spawn still
		// binds the same open file description, and a recycled descriptor number can
		// never cross-wire a different open file description into the child. the copies
		// are released by the defer once the launch settles.
		var byoPrivateCopies:[Int32] = []
		defer {
			for copy in byoPrivateCopies {
				try? copy.closeFileHandle()
			}
		}

		// validate every caller-provided descriptor before any pipe or registration
		// work happens. three checks, in order:
		//   1. the descriptor is open (`dup` fails with EBADF on a closed descriptor).
		//   2. its access mode matches the channel direction (catches swapped pipe ends).
		//   3. a private copy is taken for the spawn, as described above.
		for (fh, config) in package.dataChannels {
			let childReads:Bool
			let byoDescriptor:FileDescriptor
			switch config {
				case .read(.byo(fd:let fd)):
					childReads = true
					byoDescriptor = fd
				case .write(.byo(fd:let fd)):
					childReads = false
					byoDescriptor = fd
				default:
					continue
			}
			let privateCopy = dup(byoDescriptor.rawValue)
			guard privateCopy >= 0 else {
				throw ChildProcess.SpawnError.invalidByoFileDescriptor
			}
			// the copy is ours to mutate: mark it close-on-exec so it never leaks into
			// the child as a stray descriptor that is not part of the dup2 binding.
			_ = __cswiftslash_fcntl_setfd(privateCopy, FD_CLOEXEC)
			let accessMode = __cswiftslash_fcntl_getfl(privateCopy) & O_ACCMODE
			let directionMatches = childReads
				? (accessMode == O_RDONLY || accessMode == O_RDWR)
				: (accessMode == O_WRONLY || accessMode == O_RDWR)
			guard directionMatches else {
				// close this copy directly; its release has not been registered yet.
				try? privateCopy.closeFileHandle()
				throw ChildProcess.SpawnError.byoFileDescriptorWrongDirection
			}
			byoPrivateCopies.append(privateCopy)
			byoFdBindings[fh] = privateCopy
		}

		// pipes that will be used to facilitate io exchange with the child process.
		var processPipes = [Int32:Pipe]()
		var nullPipes = Set<PosixPipe>()

		var writeTasks = [LaunchPackage.Launched.WriteTask]()
		var readTasks = [LaunchPackage.Launched.ReadTask]()

		for (fh, config) in package.dataChannels {
			switch config {
				case .read(let writable):
					switch writable {
						case .fromParentProcess(let channel):

							let terminationFuture = Future<Void, Never>()
							
							// the child process shall read from a file handle that blocks (as is typically the case with newly launched processes). this process (parent) will write to the file handle in a non-blocking context.
							let newPipe = try PosixPipe.forChildReading()

							// create a new FIFO that is used to signal when more data can be written. since this is only a momentary signal 
							let writerFIFO = try! EventTrigger.WriterFIFO(maximumElementCount:1)

							// register the writer FH and FIFO with the event trigger so that it can signal when the file handle is ready for writing.
							try eventTrigger!.register(writer:newPipe.writing, writerFIFO, finishFuture:terminationFuture)
							
							// this pipe needs to be further handled after the process fork so we will store it for future reference.
							processPipes[fh] = .writePipe(newPipe)

							writeTasks.append(LaunchPackage.Launched.WriteTask(
								terminationFuture:terminationFuture,
								userDataStream:channel,
								writeConsumerFIFO:writerFIFO,
								wFH:newPipe.writing,
								eventTrigger:eventTrigger!
							))
						case .fromNull:
							let newPipe = try PosixPipe.createNull()
							nullPipes.insert(newPipe)
							processPipes[fh] = .writePipe(newPipe)
						case .byo(_):
							// the caller owns this descriptor end-to-end. swiftslash only
							// binds it to the child file handle; no pipe, registration, or
							// task is produced. the dup2 source binding was established by
							// the validation pass (the private copy), so nothing is done here.
							break;
						}
				case .write(let readable):
					switch readable {
						case .toParentProcess(let channel, let sep):
							
							let terminationFuture = Future<Void, DataChannel.ChildWrite.ParentRead.Error>()
							
							// the child process shall write to a file handle that blocks (as is typically the case with newly launched processes). this process (parent) will read from the file handle in a non-blocking context.
							let newPipe = try PosixPipe.forChildWriting()
							let readerFIFO = try! EventTrigger.ReaderFIFO()
							try eventTrigger!.register(reader:newPipe.reading, readerFIFO, finishFuture:terminationFuture)

							// close the writing end of the pipe after fork.
							processPipes[fh] = .readPipe(newPipe)

							readTasks.append(LaunchPackage.Launched.ReadTask(
								terminationFuture:terminationFuture,
								separator:sep,
								userDataStream:channel,
								systemReadEventsFIFO:readerFIFO,
								rFH:newPipe.reading,
								eventTrigger:eventTrigger!
							))
							break;
						case .toNull:
							let newPipe = try PosixPipe.createNull()
							processPipes[fh] = .readPipe(newPipe)
							nullPipes.insert(newPipe)
							break;
						case .byo(_):
							// the caller owns this descriptor end-to-end. swiftslash only
							// binds it to the child file handle; no pipe, registration, or
							// task is produced. the dup2 source binding was established by
							// the validation pass (the private copy), so nothing is done here.
							break;
					}
			}
		}

		// launch the application
		let launchedPID:pid_t
		do {
			launchedPID = try package.exposeArguments({ argumentArr in
				return try spawn(package.exe.path(), arguments:argumentArr, wd:package.workingDirectory.path(), env:package.env, pipes:processPipes, byoFdBindings:byoFdBindings)
			})
		} catch let error {
			// cleanup the pipes that were created.
			for curPipe in processPipes {
				switch curPipe.value {
					case .readPipe(let possibleEnabledReader):
						if nullPipes.contains(possibleEnabledReader) == false {
							try! eventTrigger!.deregister(reader:possibleEnabledReader.reading)
						}

						// the user configured this pipe to be "null piped" so we must close both ends of the pipe. this is a pipe that goes to /dev/null and our process has nothing to do with it.
						try! possibleEnabledReader.writing.closeFileHandle()
						try! possibleEnabledReader.reading.closeFileHandle()
					case .writePipe(let possibleEnabledWriter):
						if nullPipes.contains(possibleEnabledWriter) == false {
							try! eventTrigger!.deregister(writer:possibleEnabledWriter.writing)
						}

						// the user configured this pipe to be "null piped" so we must close both ends of the pipe. this is a pipe that goes to /dev/null and our process has nothing to do with it.
						try! possibleEnabledWriter.writing.closeFileHandle()
						try! possibleEnabledWriter.reading.closeFileHandle()
				}
			}
			throw error
		}
		
		// now that the child process is launched, we can close the file handles that are not intended for this process to use.
		
		for curPipe in processPipes {
			switch curPipe.value {
				case .readPipe(let possibleEnabledReader):
					if nullPipes.contains(possibleEnabledReader) == false {
						// the user configured this pipe to be "enabled" so we must close the writing end of the pipe
						try! possibleEnabledReader.writing.closeFileHandle()
					} else {
						// the user configured this pipe to be "null piped" so we must close both ends of the pipe. this is a pipe that goes to /dev/null and our process has nothing to do with it.
						try! possibleEnabledReader.writing.closeFileHandle()
						try! possibleEnabledReader.reading.closeFileHandle()
					}
				case .writePipe(let possibleEnabledWriter):
					if nullPipes.contains(possibleEnabledWriter) == false {
						// the user configured this pipe to be "enabled" so we must close the reading end of the pipe
						try! possibleEnabledWriter.reading.closeFileHandle()
					} else {
						// the user configured this pipe to be "null piped" so we must close both ends of the pipe. this is a pipe that goes to /dev/null and our process has nothing to do with it.
						try! possibleEnabledWriter.writing.closeFileHandle()
						try! possibleEnabledWriter.reading.closeFileHandle()
					}
			}
		}
		return LaunchPackage.Launched(
			writeTasks:writeTasks,
			readTasks:readTasks,
			launchedPID:launchedPID,
			eventTrigger:eventTrigger!
		)
	}

	@SwiftSlashGlobalSerialization fileprivate static func spawn(_ path:UnsafePointer<UInt8>, arguments argv:UnsafePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<UInt8>, env:[String:String], pipes:[Int32:Pipe], byoFdBindings:[Int32:Int32]) throws(ChildProcess.SpawnError) -> pid_t {
		// verify that the exec path passes initial validation.
		guard precheckExecute(path) == true else {
			throw ChildProcess.SpawnError.precheckExecutableFailure
		}

		// verify that the working directory is a valid value.
		guard precheckDirectory(wd) == true else {
			throw ChildProcess.SpawnError.precheckWorkingDirectoryFailure
		}

		// build the dup2 operations that the spawn file actions will apply in the child.
		// for each data channel we preserve the appropriate pipe end at the target file handle.
		var dup2Ops:[Int32] = []
		for (targetFH, pipe) in pipes {
			switch pipe {
				case .readPipe(let reader):
					// the child writes to targetFH. preserve the writing end of the read pipe.
					dup2Ops.append(contentsOf:[reader.writing, targetFH])
				case .writePipe(let writer):
					// the child reads from targetFH. preserve the reading end of the write pipe.
					dup2Ops.append(contentsOf:[writer.reading, targetFH])
			}
		}
		// bind any caller-provided ("bring your own") descriptors to their target file handles.
		// these descriptors are not swiftslash-owned: no flag mutation, no cleanup, no close.
		for (targetFH, callerFD) in byoFdBindings {
			dup2Ops.append(contentsOf:[callerFD, targetFH])
		}

		// build the environment as a C-style "KEY=VALUE" array. an empty dict yields
		// a pointer to a single NUL terminator, which spawns the child with an empty env
		// (matching the old clearEnvironmentVariables + setenv loop, but atomically).
		var envEntries:[UnsafeMutablePointer<CChar>?] = []
		defer {
			for entry in envEntries {
				if let entry = entry {
					free(entry)
				}
			}
		}
		for (key, value) in env {
			let entry = "\(key)=\(value)"
			if let cstr = strdup(entry) {
				envEntries.append(cstr)
			}
		}
		envEntries.append(nil)

		// invoke posix_spawn. the child performs only async-signal-safe work via
		// the spawn file actions (dup2 + optional chdir); nothing here calls fork.
		var launchedPID:pid_t = 0
		let spawnError = dup2Ops.withUnsafeBufferPointer { opsPtr in
			return envEntries.withUnsafeBufferPointer { envPtr in
				return __cswiftslash_posix_spawn(
					&launchedPID,
					path,
					argv,
					UnsafePointer<UnsafeMutablePointer<Int8>?>(envPtr.baseAddress!),
					wd,
					opsPtr.baseAddress,
					dup2Ops.count / 2
				)
			}
		}

		guard spawnError == 0 else {
			throw ChildProcess.SpawnError(fromErrno:spawnError)
		}

		return launchedPID
	}
}
