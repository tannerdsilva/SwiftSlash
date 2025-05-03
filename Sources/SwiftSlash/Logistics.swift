/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

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

internal enum WaitPIDResult {
	case signaled(Int32)
	case exited(Int32)
	case failed(errno:Int32)
}
extension pid_t {
	internal func waitPID() async -> WaitPIDResult {
		let (statusValue, errnoValue) = await withUnsafeContinuation({ (continuation:UnsafeContinuation<(Int32, Int32?), Never>) in
			var statusCapture:Int32 = 0
			let wpidReturn = waitpid(self, &statusCapture, 0)
			var errnoValue:Int32? = nil
			if wpidReturn == -1 {
				errnoValue = __cswiftslash_get_errno()
			}
			continuation.resume(returning:(statusCapture, errnoValue))
		})
		guard errnoValue == nil else {
			return WaitPIDResult.failed(errno:errnoValue!)
		}
		if __cswiftslash_eventtrigger_wifsignaled(statusValue) != 0 {
			return WaitPIDResult.signaled(__cswiftslash_eventtrigger_wtermsig(statusValue))
		} else if __cswiftslash_eventtrigger_wifexited(statusValue) != 0 {
			return WaitPIDResult.exited(__cswiftslash_eventtrigger_wexitstatus(statusValue))
		}
		fatalError("SwiftSlash WaitPID error - unrecognized exit code & status combination. this is a critical and unexpected bug. \(#file):\(#line)")
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
			exe:Path,
			arguments:[String],
			workingDirectory:Path,
			env:[String:String],
			dataChannels:[Int32:DataChannel]
		) {
			self.exe = exe
			self.arguments = arguments
			self.workingDirectory = workingDirectory
			self.env = env
			self.dataChannels = dataChannels
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
			
			internal struct WriteTask {
				internal let terminationFuture:Future<Void, DataChannel.ChildReadParentWrite.Error>
				internal let userDataStream:DataChannel.ChildReadParentWrite
				internal let writeConsumerFIFO:FIFO<Void, Never>
				internal let wFH:Int32
				internal let eventTrigger:EventTrigger<DataChannel.ChildReadParentWrite.Error, DataChannel.ChildWriteParentRead.Error>
				internal func launch(taskGroup:inout ThrowingTaskGroup<Void, Swift.Error>) {
					terminationFuture.whenResult({ [fh = wFH, et = eventTrigger, f = writeConsumerFIFO, uds = userDataStream.fifo] _ in
						try! et.deregister(writer:fh)
						f.finish()
						uds.finish()
					})
					taskGroup.addTask { [writeConsumer = writeConsumerFIFO.makeAsyncConsumerExplicit()] in
						defer {
							try! wFH.closeFileHandle()
						}

						// this function will retrieve the next data chunk that the user wants to write.
						func getNextWriteStep(iterator:borrowing FIFO<([UInt8], Future<Void, DataChannel.ChildReadParentWrite.Error>?), Never>.AsyncConsumerExplicit) async -> WriteStepper? {
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
						let terminationResult = await terminationFuture.result()!
						finalFlushLoop: while currentWriteStepper != nil {
							switch await userDataConsume.next(whenTaskCancelled:.noAction) {
								case .element(let (_, writeCompleteFuture)):
									try? writeCompleteFuture?.setResult(terminationResult)
								case .capped(_):
									// this is a signal that the file handle is not ready for writing.
									break finalFlushLoop
								case .wouldBlock:
									fatalError("SwiftSlashFIFO :: unexpected wouldBlock condition in WriteTask.launch()")
							}
						}
						return try terminationResult.get()
					}
				}
			}
			internal struct ReadTask {
				internal let terminationFuture:Future<Void, DataChannel.ChildWriteParentRead.Error>
				internal let separator:[UInt8]
				internal let userDataStream:DataChannel.ChildWriteParentRead
				internal let systemReadEventsFIFO:FIFO<size_t, Never>
				internal let rFH:Int32
				internal let eventTrigger:EventTrigger<DataChannel.ChildReadParentWrite.Error, DataChannel.ChildWriteParentRead.Error>
				internal func launch(taskGroup:inout ThrowingTaskGroup<Void, Swift.Error>) {
					terminationFuture.whenResult({ [et = eventTrigger, f = systemReadEventsFIFO] _ in
						try! et.deregister(reader:rFH)
						f.finish()
					})

					taskGroup.addTask { [systemReadEvents = systemReadEventsFIFO.makeAsyncConsumer()] in
						// this is the line parsing mechanism that allows us to separate arbitrary data into lines of a given specifier.
						var lineParser = LineParser(separator:separator, nasync:userDataStream.fifo)
						defer {
							// this is the only place where action happens with the file handle, 
							try! rFH.closeFileHandle()
							lineParser.finish()
						}
						// wait for the system to indicate that the file handle is ready for reading.
						var largestReadSize = 256
						readLoop: while let readableSize = await systemReadEvents.next(whenTaskCancelled:.finish) {
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
							var writtenCount:size_t
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
	@SwiftSlashGlobalSerialization fileprivate static var eventTrigger:EventTrigger<DataChannel.ChildReadParentWrite.Error, DataChannel.ChildWriteParentRead.Error>? = nil
	@SwiftSlashGlobalSerialization internal static func launch(package:borrowing LaunchPackage) throws -> LaunchPackage.Launched {
		if eventTrigger == nil {
			eventTrigger = try EventTrigger()
		}
		// pipes that will be used to facilitate io exchange with the child process.
		var processPipes = [Int32:Pipe]()
		var nullPipes = Set<PosixPipe>()

		var writeTasks = [LaunchPackage.Launched.WriteTask]()
		var readTasks = [LaunchPackage.Launched.ReadTask]()

		for (fh, config) in package.dataChannels {
			switch config {
				case .childReadParentWrite(let writable):
					switch writable {
						case .active(let channel):

							let terminationFuture = Future<Void, DataChannel.ChildReadParentWrite.Error>()
							
							// the child process shall read from a file handle that blocks (as is typically the case with newly launched processes). this process (parent) will write to the file handle in a non-blocking context.
							let newPipe = try PosixPipe.forChildReading()

							// create a new FIFO that is used to signal when more data can be written. since this is only a momentary signal 
							let writerFIFO = EventTrigger<DataChannel.ChildReadParentWrite.Error, DataChannel.ChildWriteParentRead.Error>.WriterFIFO(maximumElementCount:1)

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
						case .nullPipe:
							let newPipe = try PosixPipe.createNull()
							nullPipes.insert(newPipe)
							processPipes[fh] = .writePipe(newPipe)
					}
				case .childWriteParentRead(let readable):
					switch readable {
						case .active(let channel, let sep):

							let terminationFuture = Future<Void, DataChannel.ChildWriteParentRead.Error>()

							// the child process shall write to a file handle that blocks (as is typically the case with newly launched processes). this process (parent) will read from the file handle in a non-blocking context.
							let newPipe = try PosixPipe.forChildWriting()
							let readerFIFO = EventTrigger<DataChannel.ChildReadParentWrite.Error, DataChannel.ChildWriteParentRead.Error>.ReaderFIFO()
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
						case .nullPipe:
							let newPipe = try PosixPipe.createNull()
							processPipes[fh] = .readPipe(newPipe)
							nullPipes.insert(newPipe)
							break;
					}
			}
		}

		// launch the application
		let launchedPID:pid_t
		do {
			launchedPID = try package.exposeArguments({ argumentArr in
				return try spawn(package.exe.path(), arguments:argumentArr, wd:package.workingDirectory.path(), env:package.env, pipes:processPipes)
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
			launchedPID:launchedPID
		)
	}

	@SwiftSlashGlobalSerialization fileprivate static func spawn(_ path:UnsafePointer<CChar>, arguments:UnsafePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, env:[String:String], pipes:[Int32:Pipe]) throws(ProcessSpawnError) -> pid_t {
		// verify that the exec path passes initial validation.
		guard __cswiftslash_execvp_safetycheck(path) == 0 else {
			throw ProcessSpawnError.execSafetyCheckFailure
		}
		
		// open an internal posix pipe to coordinate with the child process during configuration. this function should not return until the child process has been configured.
		let internalNotify:PosixPipe
		do {
			internalNotify = try PosixPipe(nonblockingReads:false, nonblockingWrites:true)
		} catch {
			throw ProcessSpawnError.posixPipeCreateFailure
		}


		// fork the current process.
		let forkResult = __cswiftslash_fork()


		// BEGIN FORK PROCESS FUNC


		func prepareLaunch() -> Never { 
			
			// close the reading end of the internal pipe immediately after fork. the parent process will be reading, our job is to write.
			do {
				try internalNotify.reading.closeFileHandle()
			} catch {
				_ = try? internalNotify.writing.writeFH(singleByte:ProcessSpawnError.posixPipeInitialCleanupFailure.rawValue)
				try? internalNotify.writing.closeFileHandle()
				exit(Int32(ProcessSpawnError.posixPipeInitialCleanupFailure.rawValue))
			}

			// change the working directory.
			guard chdir(wd) == 0 else {
				// pass the error condition to the parent process.
				_ = try? internalNotify.writing.writeFH(singleByte:ProcessSpawnError.chdirFailure.rawValue)
				try? internalNotify.writing.closeFileHandle()
				exit(Int32(ProcessSpawnError.chdirFailure.rawValue))
			}

			// clear the environment variables inherited from the parent process.
			guard CurrentProcess.clearEnvironmentVariables() == 0 else {
				// pass the error condition to the parent process.
				_ = try? internalNotify.writing.writeFH(singleByte:ProcessSpawnError.envClearFailure.rawValue)
				try? internalNotify.writing.closeFileHandle()
				exit(Int32(ProcessSpawnError.envClearFailure.rawValue))
			}

			// assign the new environment variables.
			envVarsLoop: for (key, value) in env {
				guard setenv(key, value, 1) == 0 else {
					// pass the error condition to the parent process.
					_ = try? internalNotify.writing.writeFH(singleByte:ProcessSpawnError.envSetFailure.rawValue)
					try? internalNotify.writing.closeFileHandle()
					exit(Int32(ProcessSpawnError.envSetFailure.rawValue))
				}
			}

			pipeLoop: for (targetFH, pipe) in pipes {
				switch pipe {
					case .readPipe(let reader):
						guard dup2(reader.writing, targetFH) != -1 else {
							// pass the error condition to the parent process.
							_ = try? internalNotify.writing.writeFH(singleByte:ProcessSpawnError.dup2ReaderFailure.rawValue)
							try? internalNotify.writing.closeFileHandle()
							exit(Int32(ProcessSpawnError.dup2ReaderFailure.rawValue))
						}
						do {
							try reader.reading.closeFileHandle()
							try reader.writing.closeFileHandle()
						} catch {
							_ = try? internalNotify.writing.writeFH(singleByte:ProcessSpawnError.readerPipeCleanupFailure.rawValue)
							try? internalNotify.writing.closeFileHandle()
							exit(Int32(ProcessSpawnError.readerPipeCleanupFailure.rawValue))
						}
					case .writePipe(let writer):
						guard dup2(writer.reading, targetFH) != -1 else {
							// pass the error condition to the parent process.
							_ = try? internalNotify.writing.writeFH(singleByte:ProcessSpawnError.dup2WriterFailure.rawValue)
							try? internalNotify.writing.closeFileHandle()
							exit(Int32(ProcessSpawnError.dup2WriterFailure.rawValue))
						}
						do {
							try writer.reading.closeFileHandle()
							try writer.writing.closeFileHandle()
						} catch {
							_ = try? internalNotify.writing.writeFH(singleByte:ProcessSpawnError.writerPipeCleanupFailure.rawValue)
							try? internalNotify.writing.closeFileHandle()
							exit(Int32(ProcessSpawnError.writerPipeCleanupFailure.rawValue))
						}
				}
			}

			// loop to determine which file handles are open and close any that are not intended for this launch.
			// i dont love that this has to be here but theres no better way to reliably determine which file handles are open on the current process, let alone doing so in a remotely cross platform way.
			// as it sits, I'd much rather have this loop than have no fh cleanup at all.
			// file handles are a huge security concern, so this is an effort worth making.
			#if os(Linux)
			let fdPath = "/proc/self/fd"
			#elseif os(macOS)
			let fdPath = "/dev/fd"
			#endif
			guard let openFileHandlesPointer = opendir(fdPath) else {
				// pass the error condition to the parent process.
				_ = try? internalNotify.writing.writeFH(singleByte:ProcessSpawnError.fhCleanupDirOpenFailure.rawValue)
				try? internalNotify.writing.closeFileHandle()
				exit(Int32(ProcessSpawnError.fhCleanupDirOpenFailure.rawValue))
			}
			let dirFD = dirfd(openFileHandlesPointer)
			openFHsLoop: while let curPointer = readdir(openFileHandlesPointer) {
				withUnsafePointer(to:&curPointer.pointee.d_name) { newPointer in
					let fdString = String(cString:UnsafeRawPointer(newPointer).assumingMemoryBound(to:CChar.self))
					if fdString.contains(".") == false {
						let curFh = atoi(fdString)
						if pipes[curFh] == nil && curFh != dirFD && curFh != internalNotify.writing {
							do {
								try curFh.closeFileHandle()
							} catch {
								// pass the error condition to the parent process.
								_ = try? internalNotify.writing.writeFH(singleByte:ProcessSpawnError.fhCleanupCloseFailure.rawValue)
								try? internalNotify.writing.closeFileHandle()
								exit(Int32(ProcessSpawnError.fhCleanupCloseFailure.rawValue))
							}
						}
					}
				}
			}
			guard closedir(openFileHandlesPointer) == 0 else {
				// pass the error condition to the parent process.
				_ = try? internalNotify.writing.writeFH(singleByte:ProcessSpawnError.fhCleanupDirCloseFailure.rawValue)
				try? internalNotify.writing.closeFileHandle()
				exit(Int32(ProcessSpawnError.fhCleanupDirCloseFailure.rawValue))
			}
			
			// clean up the internal pipe
			do {
				try internalNotify.writing.closeFileHandle()
			} catch {
				_ = try? internalNotify.writing.writeFH(singleByte:ProcessSpawnError.posixPipeFinalCleanupFailure.rawValue)
				try? internalNotify.writing.closeFileHandle()
				exit(Int32(ProcessSpawnError.posixPipeFinalCleanupFailure.rawValue))
			}
			// run the process
			__cswiftslash_execvp(path, arguments)
			exit(0)
		}

		// END FORK PROCESS FUNC

		switch forkResult {
			case -1:
				// in parent: failed fork
				try! internalNotify.writing.closeFileHandle()
				try! internalNotify.reading.closeFileHandle()
				throw ProcessSpawnError.forkFailure
			case 0:
				// in child: successful fork
				prepareLaunch()
			default:
				// in parent: successful fork
				// close the writing end of the internal pipe immediately after fork. the child process will be writing here, our job is to read the other end.
				try! internalNotify.writing.closeFileHandle()
				defer {
					try! internalNotify.reading.closeFileHandle()
				}
				
				// wait for the child process to signal that it is ready to be configured.
				var byte:UInt8 = 255
				switch try! internalNotify.reading.readFH(into:&byte, size:1) {
					case 0:
						
						break;
					case 1:
						guard byte != 0 else {
							fatalError("swiftslash - internal error \(#file):\(#line)")
						}
						throw ProcessSpawnError(rawValue:byte)!
					default:
						fatalError("swiftslash - internal error \(#file) \(#line)")
				}
				
				return forkResult
		}

	}
}
