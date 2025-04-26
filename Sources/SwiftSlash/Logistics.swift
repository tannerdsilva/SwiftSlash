import __cswiftslash_posix_helpers
import __cswiftslash_eventtrigger
import SwiftSlashNAsyncStream
import SwiftSlashFHHelpers
import SwiftSlashEventTrigger
import SwiftSlashLineParser

internal enum WaitPIDResult {
	case signaled(Int32)
	case exited(Int32)
	case failed(errno:Int32)
}
extension pid_t {
	internal func waitPID() async -> WaitPIDResult {
		let (returnValue, statusValue) = await withUnsafeContinuation({ (continuation:UnsafeContinuation<(pid_t, Int32), Never>) in
			var statusCapture:Int32 = 0
			let wpidReturn = waitpid(self, &statusCapture, 0)
			continuation.resume(returning:(wpidReturn, statusCapture))
		})
		guard returnValue == self else {
			return WaitPIDResult.failed(errno:__cswiftslash_get_errno())
		}
		if __cswiftslash_eventtrigger_wifsignaled(statusValue) != 0 {
			return WaitPIDResult.signaled(__cswiftslash_eventtrigger_wtermsig(statusValue))
		} else if __cswiftslash_eventtrigger_wifexited(statusValue) != 0 {
			return WaitPIDResult.exited(__cswiftslash_eventtrigger_wexitstatus(statusValue))
		}
		fatalError("swiftslash - internal error \(#file):\(#line)")
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

		fileprivate borrowing func exposeArguments<R>(_ aHandler:(UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> R) rethrows -> R {
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

	/// the event trigger that will be used to facilitate the IO exchange between the parent and child process.
	@SerializedLaunch fileprivate static var eventTrigger:EventTrigger? = nil
	@SerializedLaunch internal static func launch(package:consuming LaunchPackage) async throws -> pid_t {
		if eventTrigger == nil {
			eventTrigger = try await EventTrigger()
		}
		return try withUnsafeMutablePointer(to:&package) { packagePtr in
			// pipes that will be used to facilitate io exchange with the child process.
			var writePipes = [Int32:PosixPipe]()
			var readPipes = [Int32:PosixPipe]()
			var nullPipes = Set<PosixPipe>()

			// configure the file handles that we will write to (process will read)
			for (fh, config) in packagePtr.pointee.writables {
				// for each writer configured...
				switch config {
					case .active(let channel):
						
						// the child process shall read from a file handle that blocks (as is typically the case with newly launched processes). this process (parent) will write to the file handle in a non-blocking context.
						let newPipe = try PosixPipe.forChildReading()

						// create a new FIFO that is used to signal when more data can be written. since this is only a momentary signal 
						let writerFIFO = EventTrigger.WriterFIFO(maximumElementCount:1)

						// register the writer FH and FIFO with the event trigger so that it can signal when the file handle is ready for writing.
						try eventTrigger!.register(writer:newPipe.writing, writerFIFO)
						
						// this pipe needs to be further handled after the process fork so we will store it for future reference.
						writePipes[fh] = newPipe
						
						// launch the writing handler task.
						Task { [ // capture some things from the current scope before escaping into the task.
							/// the user data stream that will be written to the file handle. this is where we will consume the data the user wants to write. we have an obligation to ensure the user cant pass any futures into this that we cannot fufill. therefore, finishing this and handling any contents before returning is a must.
							userDataStream = channel,
							// claim the consumer for the system write event stream.
							// despite being a fifo, we do not need to take any special steps when discarding this consumer after completing our work.
							writeConsumer = writerFIFO.makeAsyncConsumer(),
							// this is the file handle that we will write to.
							wFH = newPipe.writing,
							// this is the event trigger that we will use for register and deregister
							et = eventTrigger!
						] in
							defer {
								try! et.deregister(writer:fh)
								try! wFH.closeFileHandle()
							}

							let userDataConsume = userDataStream.makeAsyncConsumer()

							// the user data stream may be holding futures that need to be closed. these are the futures that a dev can use to wait for a chunk of data to be written before  this function will handle remaining futures from the user data stream.
							func flushRemainingFuturesFromUserStream(failure error:WrittenDataChannelClosureError) async {
								// implied task already cancelled.
								while let (_, future) = await userDataConsume.next(whenTaskCancelled:.noAction) {
									// if this chunk of data had a future associated with it, the future will be handled
									if future != nil {
										try? future!.setFailure(error)
									}
								}
							}

							// main system event loop for the file handle.
							var currentWriteStep:WriteStepper? = nil
							systemEventLoop: while await writeConsumer.next(whenTaskCancelled:.finish) != nil {
								do {
									writeAvailableLoop: repeat {
										if currentWriteStep == nil {
											if let (newUserDataToWrite, writeCompleteFuture) = await userDataConsume.next(whenTaskCancelled:.finish) {
												// apply this as the data we will step through in one or more writes.
												currentWriteStep = WriteStepper(newUserDataToWrite, writeFuture:writeCompleteFuture)
											} else {
												// user is ready for this stream to be closed.
												break systemEventLoop
											}
										}

										switch try currentWriteStep!.write(to:wFH) {
											case .retireMe:
												currentWriteStep = nil
												fallthrough
											case .holdMe:
												continue writeAvailableLoop
										}
									} while true
								} catch FileHandleError.error_wouldblock {
									// this is a non-blocking read, so we can ignore this error.
									continue systemEventLoop
								}
							}
							await flushRemainingFuturesFromUserStream(failure:WrittenDataChannelClosureError.writeLoopTaskCancelled)
						}
					case .nullPipe:
						let newPipe = try PosixPipe.createNull()
						writePipes[fh] = newPipe
						nullPipes.insert(newPipe)
						break;
				}
			}

			// configure the file handles that we will read from
			for (fh, config) in packagePtr.pointee.readables {
				switch config {
					case .active(let channel, let sep):

						// the child process shall write to a file handle that blocks (as is typically the case with newly launched processes). this process (parent) will read from the file handle in a non-blocking context.
						let newPipe = try PosixPipe.forChildWriting()
						let readerFIFO = EventTrigger.ReaderFIFO()
						try eventTrigger!.register(reader:newPipe.reading, readerFIFO)

						// close the writing end of the pipe after fork.
						readPipes[fh] = newPipe
						Task { [
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
								try! et!.deregister(reader:fh)
								// this is the only place where action happens with the file handle, 
								try! rFH.closeFileHandle()
							}
							// wait for the system to indicate that the file handle is ready for reading.
							readLoop: while let readableSize = await systemReadEvents.next(whenTaskCancelled:.finish) {
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
			let launchedPID = try packagePtr.pointee.exposeArguments({ argumentArr in
				return try spawn(packagePtr.pointee.exe.path(), arguments:argumentArr, wd:packagePtr.pointee.workingDirectory.path(), env:packagePtr.pointee.env, writePipes:writePipes, readPipes:readPipes)
			})

			// now that the child process is launched, we can close the file handles that are not intended for this process to use.
			
			// handle the write pipes
			for (_, possibleEnabledWriter) in writePipes {
				if nullPipes.contains(possibleEnabledWriter) == false {
					// the user configured this pipe to be "enabled" so we must close the reading end of the pipe
					try! possibleEnabledWriter.reading.closeFileHandle()
				} else {
					// the user configured this pipe to be "null piped" so we must close both ends of the pipe. this is a pipe that goes to /dev/null and our process has nothing to do with it.
					try! possibleEnabledWriter.writing.closeFileHandle()
					try! possibleEnabledWriter.reading.closeFileHandle()
				}
			}

			// handle the read pipes
			for (_, possibleEnabledReader) in readPipes {
				if nullPipes.contains(possibleEnabledReader) == false {
					// the user configured this pipe to be "enabled" so we must close the writing end of the pipe
					try! possibleEnabledReader.writing.closeFileHandle()
				} else {
					// the user configured this pipe to be "null piped" so we must close both ends of the pipe. this is a pipe that goes to /dev/null and our process has nothing to do with it.
					try! possibleEnabledReader.writing.closeFileHandle()
					try! possibleEnabledReader.reading.closeFileHandle()
				}
			}
			return launchedPID
		}
	}

	@SerializedLaunch fileprivate static func spawn(_ path:UnsafePointer<CChar>, arguments:UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, env:[String:String], writePipes:[Int32:PosixPipe], readPipes:[Int32:PosixPipe]) throws(ProcessSpawnError) -> pid_t {
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

			// assign the reading pipes to the child process.
			readerPipesLoop: for reader in readPipes {
				guard dup2(reader.value.reading, reader.key) != -1 else {
					// pass the error condition to the parent process.
					_ = try? internalNotify.writing.writeFH(singleByte:ProcessSpawnError.dup2ReaderFailure.rawValue)
					try? internalNotify.writing.closeFileHandle()
					exit(Int32(ProcessSpawnError.dup2ReaderFailure.rawValue))
				}
				do {
					try reader.value.reading.closeFileHandle()
					try reader.value.writing.closeFileHandle()
				} catch {
					exit(Int32(ProcessSpawnError.readerPipeCleanupFailure.rawValue))
				}
			}

			// assign the writing pipes to the child process.
			writerPipesLoop: for writer in writePipes {
				guard dup2(writer.value.writing, writer.key) != -1 else {
					// pass the error condition to the parent process.
					_ = try? internalNotify.writing.writeFH(singleByte:ProcessSpawnError.dup2WriterFailure.rawValue)
					try? internalNotify.writing.closeFileHandle()
					exit(Int32(ProcessSpawnError.dup2WriterFailure.rawValue))
				}
				do {
					try writer.value.reading.closeFileHandle()
					try writer.value.writing.closeFileHandle()
				} catch {
					exit(Int32(ProcessSpawnError.writerPipeCleanupFailure.rawValue))
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
			openFHsLoop: while let curPointer = readdir(openFileHandlesPointer) {
				withUnsafePointer(to:&curPointer.pointee.d_name) { newPointer in
					let fdString = String(cString:UnsafeRawPointer(newPointer).assumingMemoryBound(to:CChar.self))
					if fdString.contains(".") == false {
						let curFh = atoi(fdString)
						if writePipes[curFh] == nil && readPipes[curFh] == nil {
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
				exit(Int32(ProcessSpawnError.posixPipeFinalCleanupFailure.rawValue))
			}
			// run the process
			__cswiftslash_execvp(path, arguments)
			exit(0)
		}


		// END FORK PROCESS FUNC


		switch forkResult {
			case -1:
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
				do {
					var byte:UInt8 = 255
					switch try internalNotify.reading.readFH(into:&byte, size:1) {
						case 0:
							break;
						case 1:
							throw ProcessSpawnError(rawValue:byte)!
						default:
							fatalError("swiftslash - internal error \(#file) \(#line)")
					}
				} catch {
					throw ProcessSpawnError.internalFailure
				}
				
				return forkResult
		}

	}
}
