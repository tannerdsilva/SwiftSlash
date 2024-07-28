import __cswiftslash
import SwiftSlashNAsyncStream
import SwiftSlashFHHelpers
import SwiftSlashEventTrigger

public actor ProcessInterface {
	
	/// this represents the state of a process that is being managed by the ProcessInterface actor.
	public enum State:Equatable {
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
		internal let args:[String]

		// represents the working directory of the child process when it is launched.
		internal let wd:Path

		// represents the environment variables that will be assigned to the child process.
		internal let env:[String:String]

		// represents a mapping of the file handles of the child process. each file handle is written to by the parent process and read from by the child process.
		internal let writables:[Int32:DataChannel.ChildReadParentWrite.Configuration]

		// represents a mapping of the file handles of the child process. each file handle is read from by the parent process and written to by the child process.
		internal let readables:[Int32:DataChannel.ChildWriteParentRead.Configuration]

		internal borrowing func expose<R>(_ aHandler:(UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) throws -> R) rethrows -> R {
			// declare the base array for the arguments. the last element of the array is nil.
			let baseArray = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity:args.count + 1)
			defer {
				baseArray.deallocate()
			}
			// populate the base array with the arguments.
			for (i, arg) in args.enumerated() {
				baseArray[i] = strdup(arg)
			}
			// cap the base array with nil.
			baseArray[args.count] = nil
			defer {
				for i in 0..<args.count {
					free(baseArray[i])
				}
			}

			return try aHandler(baseArray)
		}
	}

	@SerializedLaunch fileprivate static func launch(package:consuming LaunchPackage, eventTrigger:borrowing EventTrigger, taskGroup:inout ThrowingTaskGroup<Void, Swift.Error>) throws {

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
					writePipes[fh] = newPipe
					taskGroup.addTask { [userDataStream = channel.makeAsyncConsumer(), writeConsumer = writerFIFO.makeAsyncConsumer(), wFH = newPipe.writing] in
						
						// write loop here
						var buffer:[UInt8] = []
						// var isWriteable: Bool = true
						systemEventLoop: while await writeConsumer.next() != nil {
							do {
								// system is indicating that the file handle is ready to be written to.
								// this inner loop will repeat until a write handle would block.
								repeat {
									// only take new data from the stream if the current write buffer is empty.
									if buffer.isEmpty {
										// does not have any data to write. wait for the user to provide some data to write.
										let newUserDataToWrite = await userDataStream.next()
										if newUserDataToWrite != nil {
											buffer.append(contentsOf:newUserDataToWrite!)
										} else {
											wFH.closeFileHandle()
											break systemEventLoop
										}
									}

									// write the data to the file handle.
									let writtenBytes = try wFH.writeFH(buffer)

									// remove the bytes that were written to the handle.
									if writtenBytes < buffer.count {
										buffer.removeFirst(writtenBytes)
									} else {
										buffer.removeAll(keepingCapacity:true)
									}
								} while true
							} catch FileHandleError.error_wouldblock {
								continue systemEventLoop
							}
						}
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
				case .active(let channel):
					// the child process shall write to a file handle that blocks (as is typically the case with newly launched processes). this process (parent) will read from the file handle in a non-blocking context.
					let newPipe = try PosixPipe.forChildWriting()
					let readerFIFO = EventTrigger.ReaderFIFO()
					try eventTrigger.register(reader:newPipe.reading, readerFIFO)
					readPipes[fh] = newPipe
					taskGroup.addTask { [userDataStream = channel, systemReadEvents = readerFIFO.makeAsyncConsumer(), rFH = newPipe.reading] in
						while let nextSize = await systemReadEvents.next() {
							let getInfo = try [UInt8](unsafeUninitializedCapacity:nextSize, initializingWith: { buff, size in
								size = try rFH.readFH(into:buff.baseAddress!, size:nextSize)
							})
						}
					}

				case .nullPipe:
					let newPipe = try PosixPipe.createNull()
					readPipes[fh] = newPipe
					nullPipes.insert(newPipe)

					break;
			}
		}


	}
	@SerializedLaunch fileprivate static func spawn(_ path:UnsafePointer<CChar>, args:UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, env:[String:String], writePipes:[Int32:PosixPipe], readPipes:[Int32:PosixPipe]) throws -> pid_t {
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

			_cswiftslash_execvp(path, args)
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
