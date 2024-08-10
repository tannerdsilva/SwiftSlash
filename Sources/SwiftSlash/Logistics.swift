import __cswiftslash
import SwiftSlashNAsyncStream
import SwiftSlashFHHelpers
import SwiftSlashEventTrigger
import SwiftSlashLineParser

public actor ProcessInterface {
	
	/// this represents the state of a process that is being managed by the ProcessInterface actor.
	public enum State:Equatable {
		/// the process interface is initialized 
		case initialized
		case launching
		case running(pid_t)
		case paused
		case signaled(Int32)
		case exited(Int32)
		case failed(Int32)
	}

	private var outbound:[Int32:NAsyncStream<[UInt8], Never>] = [:]
	private var inbound:[Int32:NAsyncStream<[UInt8], Never>] = [:]

	public var stdout:NAsyncStream<[UInt8], Never> {
		get {
			return outbound[STDOUT_FILENO]!
		}
	}
}

internal struct ProcessLogistics {

	internal struct LaunchPackage {
		// represents the path to the executable that will be launched.
		internal let exe:Path

		// represents the arguments that will be passed to the child process.
		internal let arguments:[String]

		// represents the working directory of the child process when it is launched.
		internal let workingDirectory:Path

		// represents the environment variables that will be assigned to the child process.
		internal let env:[String:String]

		// represents a mapping of the file handles of the child process. each file handle is written to by the parent process and read from by the child process.
		internal let writables:[Int32:DataChannel.ChildReadParentWrite.Configuration]

		// represents a mapping of the file handles of the child process. each file handle is read from by the parent process and written to by the child process.
		internal let readables:[Int32:DataChannel.ChildWriteParentRead.Configuration]

		internal borrowing func exposeArguments<R>(_ aHandler:(UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> R) rethrows -> R {
			// declare the base array for the arguments. the last element of the array is nil.
			let baseArray = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity:arguments.count + 1)
			defer {
				baseArray.deallocate()
			}
			// populate the base array with the arguments.
			for (i, arg) in arguments.enumerated() {
				baseArray[i] = strdup(arg)
			}
			// cap the base array with nil.
			baseArray[arguments.count] = nil
			defer {
				for i in 0..<arguments.count {
					free(baseArray[i])
				}
			}
			return try aHandler(baseArray)
		}
	}

	@SerializedLaunch fileprivate static func launch(package:consuming LaunchPackage, eventTrigger:EventTrigger, taskGroup:inout ThrowingTaskGroup<Void, Swift.Error>) throws -> pid_t {
		var writePipes = [Int32:PosixPipe]()
		var readPipes = [Int32:PosixPipe]()
		var nullPipes = Set<PosixPipe>()

		// configure the file handles that we will write to
		for (fh, config) in package.writables {
			switch config {
				case .active(let channel):
					
					// the child process shall read from a file handle that blocks (as is typically the case with newly launched processes). this process (parent) will write to the file handle in a non-blocking context.
					let newPipe = try PosixPipe.forChildReading()
					let writerFIFO = EventTrigger.WriterFIFO(maximumElementCount:1)
					try eventTrigger.register(writer:newPipe.writing, writerFIFO)
					
					// close the reading end of the pipe after fork.
					writePipes[fh] = newPipe
					
					// launch the writing task.
					taskGroup.addTask { [ // capture some things from the current scope before escaping into the task.
						/// the user data stream that will be written to the file handle. this is where we will consume the data the user wants to write. we have an obligation to ensure the user cant pass any futures into this that we cannot fufill. therefore, finishing this and handling any contents before returning is a must.
						userDataStream = channel,
						// claim the consumer for the system write event stream.
						// despite being a fifo, we do not need to take any special steps when discarding this consumer after completing our work.
						writeConsumer = writerFIFO.makeAsyncConsumer(),
						// this is the file handle that we will write to.
						wFH = newPipe.writing,
						// this is the event trigger that we will use for register and deregister
						et = eventTrigger
					] in
						defer {
							try! et.deregister(writer:fh)
							wFH.closeFileHandle()
						}

						let userDataConsume = userDataStream.makeAsyncConsumer()

						// represents the main work that coordinates the written channel with the system file handle
						func mainWork(_ currentStep:inout WriteStepper?) async throws {
							defer {
								// the user data stream should not store any more values after the main work returns.
								userDataStream.finish()
							}
							// main system event loop for the file handle.
							systemEventLoop: while let _ = try await writeConsumer.next(whenTaskCancelled:.finish) {
								do {
									// system is indicating that the file handle is ready to be written to.

									// this inner loop will repeat until a write handle would block.
									writeAvailLoop: repeat {

										// only take new data from the stream if the current write buffer is empty.
										if currentStep == nil {

											// does not have any data to write. wait for the user to provide some data to write.
											if let (newUserDataToWrite, writeCompleteFuture) = await userDataConsume.next(whenTaskCancelled:.finish) {
												// apply this as the data we will step through in one or more writes.
												currentStep = WriteStepper(newUserDataToWrite, writeFuture:writeCompleteFuture)
											} else {
												// user is ready for this stream to be closed.
												break systemEventLoop
											}
										}

										// write the data to the file handle.
										switch try currentStep!.write(to:wFH) {
											case .retireMe:
												currentStep = nil
												fallthrough
											case .holdMe:
												continue writeAvailLoop
										}
									} while true
								} catch FileHandleError.error_wouldblock {
									continue systemEventLoop
								}
							}
						}

						// the user data stream may be holding futures that need to be closed. this function will handle remaining futures from the user data stream.
						func flushRemainingFuturesFromUserStream(failure error:Swift.Error) async {
							// implied task already cancelled.
							while let (_, future) = await userDataConsume.next(whenTaskCancelled:.noAction) {
								if future != nil {
									try? future!.setFailure(error)
								}
							}
						}

						var currentStep:WriteStepper? = nil
						do {
							// do the main work.
							try await mainWork(&currentStep)

							// if there is any outbound data remaining in the stepper, we must notify that the data was not written.
							if let currentStep = currentStep {
								try? currentStep.completeFuture?.setFailure(DataChannelClosedError())
							}
						} catch let error {
							// if there is any outbound data remaining in the stepper, we must notify that the data was not written.
							if let currentStep = currentStep {
								try? currentStep.completeFuture?.setFailure(error)
							}
						}
						await flushRemainingFuturesFromUserStream(failure:DataChannelClosedError())
					}
				case .nullPipe:
					let newPipe = try PosixPipe.createNull()
					writePipes[fh] = newPipe
					nullPipes.insert(newPipe)
					break;
			}
		}

		// configure the file handles that we will read from
		for (fh, config) in package.readables {
			switch config {
				case .active(let channel, let sep):

					// the child process shall write to a file handle that blocks (as is typically the case with newly launched processes). this process (parent) will read from the file handle in a non-blocking context.
					let newPipe = try PosixPipe.forChildWriting()
					let readerFIFO = EventTrigger.ReaderFIFO()
					try eventTrigger.register(reader:newPipe.reading, readerFIFO)

					// close the writing end of the pipe after fork.
					readPipes[fh] = newPipe
					taskGroup.addTask { [
						/// the user data stream that we will pass the parsed data into. the main purpose of this task is to execute the read when the system indicates it is time to do so. the data is then passed into a line parser that is configured to the users specifications. the resulting output of the line parser will go through this channel.
						userDataStream = channel,
						/// this is the FIFO that the system uses to signal to this task that it is time to read from the file handle.
						systemReadEvents = readerFIFO.makeAsyncConsumer(),
						/// this is the file handle that we will read from.
						rFH = newPipe.reading,
						/// this is the event trigger that we will use for register and deregister
						et = eventTrigger
					] in
						// this is the line parsing mechanism that allows us to separate arbitrary data into lines of a given specifier.
						var lineParser = LineParser(separator:sep, nasync:userDataStream.nasync)
						defer {
							// file handle should not remain registered after this task is complete.
							try! et.deregister(reader:fh)
							// this is the only place where action happens with the file handle, 
							rFH.closeFileHandle()
						}
						// wait for the system to indicate that the file handle is ready for reading.
						readLoop: while let readableSize = try await systemReadEvents.next(whenTaskCancelled:.finish) {
							do {
								// prepare the lineparser to intake the data.
								try lineParser.intake(bytes:readableSize) { wptr in
									// read the data directly from the handle to the lineparser.
									return try rFH.readFH(into:wptr.baseAddress!, size:readableSize)
								}
							} catch FileHandleError.error_wouldblock {
								continue readLoop
							}
						}
					}

				case .nullPipe:
					let newPipe = try PosixPipe.createNull()
					readPipes[fh] = newPipe
					nullPipes.insert(newPipe)
					break;
			}
		}

		// launch the application
		let launchedPID = try package.exposeArguments({ argumentArr in
			return try spawn(package.exe.path(), arguments:argumentArr, wd:package.workingDirectory.path(), env:package.env, writePipes:writePipes, readPipes:readPipes)
		})

		// now that the child process is launched, we can close the file handles that are not intended for this process to use.
		
		// handle the write pipes
		for (_, possibleEnabledWriter) in writePipes {
			if nullPipes.contains(possibleEnabledWriter) == false {
				// the user configured this pipe to be "enabled" so we must close the reading end of the pipe
				possibleEnabledWriter.reading.closeFileHandle()
			} else {
				// the user configured this pipe to be "null piped" so we must close both ends of the pipe. this is a pipe that goes to /dev/null and our process has nothing to do with it.
				possibleEnabledWriter.writing.closeFileHandle()
				possibleEnabledWriter.reading.closeFileHandle()
			}
		}

		// handle the read pipes
		for (_, possibleEnabledReader) in readPipes {
			if nullPipes.contains(possibleEnabledReader) == false {
				// the user configured this pipe to be "enabled" so we must close the writing end of the pipe
				possibleEnabledReader.writing.closeFileHandle()
			} else {
				// the user configured this pipe to be "null piped" so we must close both ends of the pipe. this is a pipe that goes to /dev/null and our process has nothing to do with it.
				possibleEnabledReader.writing.closeFileHandle()
				possibleEnabledReader.reading.closeFileHandle()
			}
		}

		return launchedPID
	}

	@SerializedLaunch fileprivate static func spawn(_ path:UnsafePointer<CChar>, arguments:UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, env:[String:String], writePipes:[Int32:PosixPipe], readPipes:[Int32:PosixPipe]) throws -> pid_t {
		// open an internal posix pipe to coordinate with the child process during configuration. this function should not return until the child process has been configured.
		let internalNotify = try PosixPipe(nonblockingReads:false, nonblockingWrites:true)

		// fork the current process.
		let forkResult = _cswiftslash_fork()


		// BEGIN FORK PROCESS FUNC


		func prepareLaunch() -> Never { 
			
			// close the reading end of the internal pipe immediately after fork. the parent process will be reading, our job is to write.
			internalNotify.reading.closeFileHandle()

			// enable cloexec on our writer.
			let existingFlags = fcntl(internalNotify.writing, F_GETFD)
			guard existingFlags != -1 else {
				_ = try? internalNotify.writing.writeFH([1])
				exit(60)
			}
			guard fcntl(internalNotify.writing, F_SETFD, existingFlags | FD_CLOEXEC) != -1 else {
				_ = try? internalNotify.writing.writeFH([1])
				exit(61)
			}

			// change the working directory.
			guard chdir(wd) == 0 else {
				_ = try? internalNotify.writing.writeFH([1])
				exit(40)
			}

			// clear the environment variables inherited from the parent process.
			guard CurrentProcess.clearEnvironmentVariables() == 0 else {
				_ = try? internalNotify.writing.writeFH([1])
				exit(41)
			}

			// assign the new environment variables.
			for (key, value) in env {
				guard setenv(key, value, 1) == 0 else {
					_ = try? internalNotify.writing.writeFH([1])
					exit(42)
				}
			}

			// asssign the raeding pipes to the child process.
			for reader in readPipes {
				guard dup2(reader.value.reading, reader.key) != -1 else {
					_ = try? internalNotify.writing.writeFH([1])
					exit(43)
				}
				close(reader.value.reading)
				close(reader.value.writing)
			}

			// assign the writing pipes to the child process.
			for writer in writePipes {
				guard dup2(writer.value.writing, writer.key) != -1 else {
					_ = try? internalNotify.writing.writeFH([1])
					exit(44)
				}
				close(writer.value.reading)
				close(writer.value.writing)
			}

			// determine which file handles are open and close any that are not intended for this launch.
			#if os(Linux)
			let fdPath = "/proc/self/fd"
			#elseif os(macOS)
			let fdPath = "/dev/fd"
			#endif
			guard let openFileHandlesPointer = opendir(fdPath) else {
				_ = try? internalNotify.writing.writeFH([1])
				exit(50)
			}
			while let curPointer = readdir(openFileHandlesPointer) {
				withUnsafePointer(to:&curPointer.pointee.d_name) { newPointer in
					let fdString = String(cString:UnsafeRawPointer(newPointer).assumingMemoryBound(to: CChar.self))
					if fdString.contains(".") == false {
						let curFh = atoi(fdString)
						if writePipes[curFh] == nil && readPipes[curFh] == nil {
							close(curFh)
						}
					}
				}
			}
			closedir(openFileHandlesPointer)

			_cswiftslash_execvp(path, arguments)
			exit(0)
		}


		// END FORK PROCESS FUNC


		switch forkResult {
			case -1:
				throw SystemErrno(errno)
			case 0:
				// in child: successful fork
				prepareLaunch()
			default:
				// in parent: successful fork
				// close the writing end of the internal pipe immediately after fork. the child process will be writing here, our job is to read the other end.
				internalNotify.writing.closeFileHandle()
				defer {
					internalNotify.reading.closeFileHandle()
				}

				// wait for the child process to signal that it is ready to be configured.
				var byte:UInt8 = 255
				switch try internalNotify.reading.readFH(into:&byte, size:1) {
					case 0:
						break;
					case 1:
						guard byte == 1 else {
							throw InternalLaunchError()
						}
					default:
						fatalError("swiftslash - internal error \(#file) \(#line)")
				}
				
				return forkResult
		}

	}
}

/// check if a path is a directory and is accessible for execution.
fileprivate func directoryCheck(_ p:consuming Path) -> Bool {
	func _dc(_ p:UnsafePointer<UInt8>) -> Bool {
		var s = stat()
		guard stat(p, &s) == 0, s.st_mode & S_IFMT == S_IFDIR else {
			return false
		}
		guard access(p, R_OK | X_OK) == 0 else {
			return false
		}
		return true
	}
	return _dc(p.path())
}

/// check if a path is a file and is accessible for execution.
fileprivate func executeCheck(_ p:consuming Path) -> Bool {
	func _ec(_ p:UnsafePointer<UInt8>) -> Bool {
		var s = stat()
		guard stat(p, &s) == 0, s.st_mode & S_IFMT == S_IFREG else {
			return false
		}
		guard access(p, R_OK | X_OK) == 0 else {
			return false
		}
		return true
	}
	return _ec(p.path())
}
