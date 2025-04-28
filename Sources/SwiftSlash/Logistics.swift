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
import SwiftSlashLineParser
import SwiftSlashFIFO
import SwiftSlashFuture

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
		fatalError("swiftslash - internal error \(#file):\(#line)")
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
		/// represents a mapping of the file handles of the child process. each file handle is written to by the parent process and read from by the child process.
		internal let writables:[Int32:DataChannel.ChildReadParentWrite.Configuration]
		/// represents a mapping of the file handles of the child process. each file handle is read from by the parent process and written to by the child process.
		internal let readables:[Int32:DataChannel.ChildWriteParentRead.Configuration]

		/// expose all of the arguments for this launch package as c pointers that could be used to launch a child process.
		fileprivate borrowing func exposeArguments<R>(_ aHandler:(UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> R) rethrows -> R {
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
				internal let finishFuture:Future<Void, Never>
				internal let userDataStream:DataChannel.ChildReadParentWrite
				internal let writeConsumerFIFO:FIFO<Void, Never>
				internal let wFH:Int32
				internal let eventTrigger:EventTrigger
				internal func launch(taskGroup:inout ThrowingTaskGroup<Void, Swift.Error>) {
					finishFuture.whenResult { [userData = userDataStream] _ in
						userData.finish()
					}
					taskGroup.addTask { [writeConsumer = writeConsumerFIFO.makeAsyncConsumer()] in
						defer {
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

								do {
									switch try currentWriteStep!.write(to:wFH) {
										case .retireMe:
											currentWriteStep = nil
											fallthrough
										case .holdMe:
											continue writeAvailableLoop
									}
								} catch FileHandleError.error_wouldblock {
									// go back to the system event loop and wait for the file handle to be ready for more writing.
									continue systemEventLoop
								} catch let error as FileHandleError {
									// this is a problem with the file handle itself. we need to close the file handle and signal to the user that this is a problem.
									await flushRemainingFuturesFromUserStream(failure:WrittenDataChannelClosureError.systemWriteErrorThrown(error))
									throw error
								}
							} while true
						}
						if Task.isCancelled == false {
							
						} else {

						}
						await flushRemainingFuturesFromUserStream(failure:WrittenDataChannelClosureError.writeLoopTaskCancelled)
					}
				}
			}
			internal struct ReadTask {
				internal let finishFuture:Future<Void, Never>
				internal let separator:[UInt8]
				internal let userDataStream:DataChannel.ChildWriteParentRead
				internal let systemReadEventsFIFO:FIFO<size_t, Never>
				internal let rFH:Int32
				internal let eventTrigger:EventTrigger
				internal func launch(taskGroup:inout ThrowingTaskGroup<Void, Swift.Error>) {
					finishFuture.whenResult { [userData = userDataStream] _ in
						userData.finish()
					}
					taskGroup.addTask { [systemReadEvents = systemReadEventsFIFO.makeAsyncConsumer()] in
						// this is the line parsing mechanism that allows us to separate arbitrary data into lines of a given specifier.
						var lineParser = LineParser(separator:separator, nasync:userDataStream.nasync)
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

	/// the event trigger that will be used to facilitate the IO exchange between the parent and child process.
	@SerializedLaunch fileprivate static var eventTrigger:EventTrigger? = nil
	@SerializedLaunch internal static func launch(package:borrowing LaunchPackage) throws -> LaunchPackage.Launched {
		if eventTrigger == nil {
			eventTrigger = try EventTrigger()
		}
		// pipes that will be used to facilitate io exchange with the child process.
		var writePipes = [Int32:PosixPipe]()
		var readPipes = [Int32:PosixPipe]()
		var nullPipes = Set<PosixPipe>()

		var writeTasks = [LaunchPackage.Launched.WriteTask]()
		var readTasks = [LaunchPackage.Launched.ReadTask]()

		// configure the file handles that we will write to (process will read)
		for (fh, config) in package.writables {
			// for each writer configured...
			switch config {
				case .active(let channel):

					let finishFuture = Future<Void, Never>()
					
					// the child process shall read from a file handle that blocks (as is typically the case with newly launched processes). this process (parent) will write to the file handle in a non-blocking context.
					let newPipe = try PosixPipe.forChildReading()

					// create a new FIFO that is used to signal when more data can be written. since this is only a momentary signal 
					let writerFIFO = EventTrigger.WriterFIFO(maximumElementCount:1)

					// register the writer FH and FIFO with the event trigger so that it can signal when the file handle is ready for writing.
					try eventTrigger!.register(writer:newPipe.writing, writerFIFO, finishFuture:finishFuture)
					
					// this pipe needs to be further handled after the process fork so we will store it for future reference.
					writePipes[fh] = newPipe

					writeTasks.append(LaunchPackage.Launched.WriteTask(
						finishFuture:finishFuture,
						userDataStream:channel,
						writeConsumerFIFO:writerFIFO,
						wFH:newPipe.writing,
						eventTrigger:eventTrigger!
					))
					
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

					let finishFuture = Future<Void, Never>()

					// the child process shall write to a file handle that blocks (as is typically the case with newly launched processes). this process (parent) will read from the file handle in a non-blocking context.
					let newPipe = try PosixPipe.forChildWriting()
					let readerFIFO = EventTrigger.ReaderFIFO()
					try eventTrigger!.register(reader:newPipe.reading, readerFIFO, finishFuture:finishFuture)

					// close the writing end of the pipe after fork.
					readPipes[fh] = newPipe

					readTasks.append(LaunchPackage.Launched.ReadTask(
						finishFuture:finishFuture,
						separator:sep,
						userDataStream:channel,
						systemReadEventsFIFO:readerFIFO,
						rFH:newPipe.reading,
						eventTrigger:eventTrigger!
					))
					
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

		return LaunchPackage.Launched(
			writeTasks:writeTasks,
			readTasks:readTasks,
			launchedPID:launchedPID
		)
	}

	@SerializedLaunch fileprivate static func spawn(_ path:UnsafePointer<CChar>, arguments:UnsafePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, env:[String:String], writePipes:[Int32:PosixPipe], readPipes:[Int32:PosixPipe]) throws(ProcessSpawnError) -> pid_t {
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

			// assign the reading pipes to the child process.
			readerPipesLoop: for (targetFH, reader) in readPipes {
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
			}

			// assign the writing pipes to the child process.
			writerPipesLoop: for (targetFH, writer) in writePipes {
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
						if writePipes[curFh] == nil && readPipes[curFh] == nil && curFh != dirFD && curFh != internalNotify.writing {
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
