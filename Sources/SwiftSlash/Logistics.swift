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
	}

	@SerializedLaunch fileprivate static func launch(package:consuming LaunchPackage, eventTrigger:borrowing EventTrigger, taskGroup:inout ThrowingTaskGroup<Void, Swift.Error>) {
		var fhReadersToDeregisterIfThrown = Set<Int32>() // if throw dereg read
		var fhWritersToDeregisterIfThrown = Set<Int32>() // if throw dereg write
		var fhToCloseIfThrown = Set<Int32>() // ?

		// also what are these?
		var removeReadersFromSelfIfThrown = Set<Int32>() 
		var removeWritersFromSelfIfThrown = Set<Int32>()

		do {
			// var buildOut = [Int32:(PosixPipe, EventTrigger.WriterFIFO, DataChannel.Outbound?)]()
			for (fh, config) in package.writables {
				switch config {
					case .active(let channel):
						let newPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:true)
						let writerFIFO = EventTrigger.WriterFIFO(maximumElementCount:1)
						try eventTrigger.register(writer:newPipe.writing, writerFIFO)
						taskGroup.addTask { [userDataStream = channel.makeAsyncConsumer(), writeConsumer = writerFIFO.makeAsyncConsumer(), wFH = newPipe.writing] in
							// write loop here
							var currentWrite:[UInt8] = []
							writableEventLoop: while await writeConsumer.next() != nil {
								if let newUserDataToWrite = await userDataStream.next() {
									currentWrite.append(contentsOf:newUserDataToWrite)
								} else {
									break writableEventLoop
								}
								let writtenBytes = try newPipe.writing.writeFH(currentWrite)
								if writtenBytes < currentWrite.count {
									currentWrite.removeFirst(writtenBytes)
								} else {
									currentWrite.removeAll(keepingCapacity:true)
								}
							}
						}
					// case .closed:
					// 	buildOut[fh] = (nil, EventTrigger.WriterFIFO(), nil)
					case .nullPipe:
					break;
						// buildOut[fh] = (nil, EventTrigger.WriterFIFO(), nil)
				}
			}
		} catch let error {

		}
	}
	@SerializedLaunch fileprivate static func spawn(_ path:UnsafePointer<Int8>, args:UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, env:[String:String], writePipes:[Int32:PosixPipe], readPipes:[Int32:PosixPipe]) throws -> pid_t {
		// open an internal posix pipe to coordinate with the child process during configuration. this function should not return until the child process has been configured.
		let internalNotify = try PosixPipe(nonblockingReads:false, nonblockingWrites:true)

		// fork the current process.
		let forkResult = _cswiftslash_fork()


		// BEGIN FORK PROCESS FUNC


		func prepareLaunch() -> Never { 
			
			// close the reading end of the internal pipe immediately after fork. the parent process will be reading, our job is to write.
			internalNotify.reading.closeFileHandle()

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

			_ = try! internalNotify.writing.writeFH([0])

			internalNotify.writing.closeFileHandle()
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
				guard try internalNotify.reading.readFH(into:&byte, size:1) == 1, byte == 0 else {
					throw InternalLaunchError()
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
