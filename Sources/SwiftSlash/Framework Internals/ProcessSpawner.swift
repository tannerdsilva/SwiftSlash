import Foundation
import Glibc
import Cfork

fileprivate func _WSTATUS(_ status:Int32) -> Int32 {
	return status & 0x7f
}
fileprivate func WIFEXITED(_ status:Int32) -> Bool {
	return _WSTATUS(status) == 0
}
fileprivate func WEXITSTATUS(_ status: CInt) -> CInt {
	return (status >> 8) & 0xff
}

extension Array where Element == String {
	//will convert a swift array of execution arguments to a buffer pointer that tt_spawn can use at a lower levels
	internal func with_spawn_ready_arguments<R>(_ work:@escaping(UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>) throws -> R) rethrows -> R {
		let argC = self.withUnsafeBufferPointer { (pointer) -> UnsafeMutablePointer<UnsafeMutablePointer<Int8>?> in
			let arr:UnsafeBufferPointer<String> = pointer
			let buff = UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>.allocate(capacity:arr.count + 1)
			buff.initialize(from:arr.map { $0.withCString(strdup) }, count:arr.count)
			buff[arr.count] = nil
			return buff
		}
		defer {
			for arg in argC ..< argC + count {
				free(UnsafeMutableRawPointer(arg.pointee))
			}
			argC.deallocate()
		}
		return try work(argC)
	}
}

extension Dictionary where Key == String, Value == String {
	internal func with_spawn_ready_environment<R>(_ work:@escaping([UnsafeMutablePointer<Int8>]) throws -> R) rethrows -> R {
		let cEnv = self.compactMap { strdup("\($0)=\($1)") }
		defer {
			for (_, curPtr) in cEnv.enumerated() {
				free(UnsafeMutableRawPointer(curPtr))
			}
		}
		return try work(cEnv)
	}
}

extension pid_t {
	internal func getExitCode() -> Int32? {
		var waitResult:Int32 = 0
		var exitCode:Int32 = 0
		var errNo:Int32 = 0
		repeat {
			waitResult = waitpid(self, &exitCode, 0)
			errNo = errno
		} while waitResult == -1 && errNo == EINTR
		if WIFEXITED(exitCode) == true {
			return WEXITSTATUS(exitCode)
		} else {
			return nil
		}
	}
}


//this is the structure that is used to capture all relevant information about a process that is in flight
internal struct ProcessSignature:Hashable {
	let stdin:PosixPipe
	let stdout:PosixPipe
	let stderr:PosixPipe

	let stdinChannel:OutboundChannelState

	let worker:pid_t

	let launch_time:Date

	//initialize
	init(work:pid_t, stdin:PosixPipe, stdout:PosixPipe, stderr:PosixPipe, stdinChannel:OutboundChannelState) {
		self.worker = work
		self.launch_time = Date()
	
		self.stdin = stdin
		self.stderr = stderr
		self.stdout = stdout
		
		self.stdinChannel = stdinChannel
	}

	//comparable
	static func == (lhs:ProcessSignature, rhs:ProcessSignature) -> Bool {
		return lhs.stderr == rhs.stderr && lhs.stdout == rhs.stdout && lhs.stdin == rhs.stdin && lhs.worker == rhs.worker
	}

	//hashable
	func hash(into hasher:inout Hasher) {
		//standard input channel is always going to be utilized
		hasher.combine(stdin.writing)
		hasher.combine(stdin.reading)
		
		if stdout.isNullValued == false  {
			hasher.combine(stdout.writing)
			hasher.combine(stdout.reading)
		}
		if stderr.isNullValued == false {
			hasher.combine(stderr.writing)
			hasher.combine(stderr.reading)
		}
	
		hasher.combine(worker)
		hasher.combine(launch_time)
	}
}

internal actor ProcessSpawner {
	enum Error:Swift.Error {
		case badAccess
		case internalError
		case systemForkErrorno(Int32)
		case pipeError
	}
	
	static let global = ProcessSpawner()
	
	func launch(path:String, args:[String], wd:URL, env:[String:String], stdout:AsyncStream<Data>.Continuation?, stdoutParseMode:DataParseMode, stderr:AsyncStream<Data>.Continuation?, stderrParseMode:DataParseMode, initialStdin:Data? = nil) async throws -> ProcessSignature {
		let stdoutPipe:PosixPipe
		let stderrPipe:PosixPipe
		let stdinPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:true)
		
		guard stdinPipe.reading != -1 && stdinPipe.writing != -1 else {
			throw Error.pipeError
		}
		
		let terminationGroup = TerminationGroup(fhs:Set<Int32>([stdinPipe.writing]))
		
		let writeConfig = WritableConfiguration(fh:stdinPipe.writing, group:terminationGroup)
		var readConfigs = [ReadableConfiguration]()

		//configure for a standard output handler if the user passed a handler block
		if stdout != nil {
			stdoutPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:true)
			await terminationGroup.includeHandle(fh:stdoutPipe.reading)
			readConfigs.append(ReadableConfiguration(fh:stdoutPipe.reading, parseMode:stdoutParseMode, group:terminationGroup, continuation:stdout!))
			guard stdoutPipe.isNullValued == false else {
				throw Error.pipeError
			}
		} else {
			stdoutPipe = PosixPipe(reading:-1, writing:-1)
		}
		
		//configure for a standard error handler if the user passed a handler block
		if stderr != nil {
			stderrPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:true)
			await terminationGroup.includeHandle(fh:stderrPipe.reading)
			readConfigs.append(ReadableConfiguration(fh:stderrPipe.reading, parseMode:stderrParseMode, group:terminationGroup, continuation:stderr!))
			guard stderrPipe.isNullValued == false else {
				throw Error.pipeError
			}
		} else {
			stderrPipe = PosixPipe(reading:-1, writing:-1)
		}
		
		let stdinChannel = try await EventSwarm.global.register(readers:readConfigs, writer:writeConfig)
	
		let returnVal = try path.withCString({ executablePathPointer -> pid_t in
			var argBuild = [path]
			argBuild.append(contentsOf:args)
			return try argBuild.with_spawn_ready_arguments({ argumentsToSpawn in
				return try wd.path.withCString({ workingDirectoryPath in
					return try tt_spawn(path:executablePathPointer, args:argumentsToSpawn, wd:workingDirectoryPath, env:env, stdin:stdinPipe, stdout:stdoutPipe, stderr:stderrPipe)
				})
			})
		})
		
		if (initialStdin != nil) {
			await stdinChannel.broadcast(initialStdin!)
		}
		await terminationGroup.setAssociatedPid(returnVal)
		
		return ProcessSignature(work:returnVal, stdin:stdinPipe, stdout:stdoutPipe, stderr:stderrPipe, stdinChannel:stdinChannel)
	}
}

fileprivate func tt_spawn(path:UnsafePointer<Int8>, args:UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, env:[String:String], stdin:PosixPipe, stdout:PosixPipe, stderr:PosixPipe) throws -> pid_t {
	//used internally for this function to determine when the forked process has successfully initialized
	let internalNotify = try PosixPipe(nonblockingReads:false, nonblockingWrites:true)
	guard internalNotify.isNullValued == false else {
		throw ProcessSpawner.Error.pipeError
	}
	
	guard tt_directory_check(ptr:wd) == true && tt_execute_check(ptr:path) == true else {
		throw ProcessSpawner.Error.badAccess
	}
	
	let forkResult = cfork()	//spawn the container process
		
	func prepareLaunch() -> Never {
		//close the reading end of the pipe immediately
		_ = close(internalNotify.reading)
	
		//bind the IO to the standard inputs and outputs.
		do {
			func bindingStdout() throws -> PosixPipe {
				if stdout.isNullValued == true {
					return try PosixPipe.createNullPipe()
				} else {
					return stdout
				}
			}
			func bindingStderr() throws -> PosixPipe {
				if stderr.isNullValued == true {
					return try PosixPipe.createNullPipe()
				} else {
					return stderr
				}
			}

			//assign stdout to the writing end of the file descriptor
			let hasStdout:PosixPipe = try bindingStdout()
			defer {
				if (hasStdout.isNullValued == false) {
					_ = close(hasStdout.writing)
					_ = close(hasStdout.reading)
				}
			}
			guard dup2(hasStdout.writing, STDOUT_FILENO) >= 0 else {
				_ = try? internalNotify.writing.writeFileHandle("1")
				exit(250)
			}
		
			//assign stderr to the writing end of the file descriptor
			let hasStderr:PosixPipe = try bindingStderr()
			defer {
				if (hasStderr.isNullValued == false) {
					_ = close(hasStderr.writing)
					_ = close(hasStderr.reading)
				}
			}
			guard dup2(hasStderr.writing, STDERR_FILENO) >= 0 else {
				_ = try? internalNotify.writing.writeFileHandle("1")
				exit(250)
			}

			//assign stdin to the writing end of the file descriptor
			let hasStdin:PosixPipe = stdin
			defer {
				_ = close(hasStdin.writing)
				_ = close(hasStdin.reading)
			}
			guard dup2(stdin.reading, STDIN_FILENO) >= 0 else {
				_ = try? internalNotify.writing.writeFileHandle("1")
				exit(250)
			}
		} catch _ {
			_ = try? internalNotify.writing.writeFileHandle("1")
			exit(250)
		}
	
		//change the active directory
		guard chdir(wd) == 0 else {
			_ = try? internalNotify.writing.writeFileHandle("1")
			exit(250)
		}
	
		//clear the old environment variables and assign the new ones
		guard clearenv() == 0 else {
			_ = try? internalNotify.writing.writeFileHandle("1")
			exit(250)
		}
		for(_, kv) in env.enumerated() {
			kv.key.withCString { keyPointer in
				kv.value.withCString { valuePointer in
					guard setenv(keyPointer, valuePointer, 1) == 0 else {
						_ = try? internalNotify.writing.writeFileHandle("1")
						exit(250)
					}
				}
			}
		}
	
		//close any open file handles (excluding standard datas and the internal tt_spawn pipe)
		guard let openFileHandlesPointer = opendir("/proc/self/fd/") else {
			_ = try? internalNotify.writing.writeFileHandle("1")
			exit(250)
		}
		while let curPointer = readdir(openFileHandlesPointer) {
			withUnsafePointer(to:&curPointer.pointee.d_name) { pointer in
				let buffer = UnsafeRawPointer(pointer).assumingMemoryBound(to:Int8.self)
				let length = strlen(buffer)
				let data = Data(bytes:buffer, count:length)
				let asString = String(data:data, encoding:.utf8)!
				if let curFh = Int32(asString) {
					if (curFh != STDIN_FILENO && curFh != STDOUT_FILENO && curFh != STDERR_FILENO && curFh != internalNotify.writing) {
						close(curFh)
					}
				}
			}
		}
		closedir(openFileHandlesPointer)
	
		_ = try! internalNotify.writing.writeFileHandle("0")
		_ = close(internalNotify.writing)
	
		Glibc.execvp(path, args)
		exit(0)
	}

	//handle the result of the first fork call
	switch forkResult {
		case -1:
			//in parent, error
			throw ProcessSpawner.Error.systemForkErrorno(errno)
		case 0:
			//in child: success
			prepareLaunch()
	
		default:
			//in parent, success
		
			//configure the file handles for the context of the parent process synchronously
			close(internalNotify.writing)
			close(stdin.reading)
			close(stderr.writing)
			close(stdout.writing)
			
			//wait for data to appear in the internalNotify pipe
			var shouldLoop = false
			var triggerData = Data()
			repeat {
				do {
					try triggerData.append(contentsOf:internalNotify.reading.readFileHandle(size:Int(PIPE_BUF)))
					shouldLoop = false
				} catch FileHandleError.error_again {
					shouldLoop = true
				} catch FileHandleError.error_wouldblock {
					shouldLoop = true
				} catch _ {
					shouldLoop = false
				}
			} while shouldLoop == true
			//close the internal notify switch in the background
			close(internalNotify.reading)
		
			//parse the data that was received in the internalNotify pipe
			guard triggerData.count > 0 else {
				throw ProcessSpawner.Error.internalError
			}
			guard let notifyString = String(data:triggerData, encoding:.utf8) else {
				throw ProcessSpawner.Error.internalError
			}
			guard notifyString == "0" else {
				throw ProcessSpawner.Error.internalError
			}
		
			return forkResult
	}
}

//MARK: Small Helpers
//check if a path is executable
internal func tt_execute_check(url:URL) -> Bool {
	let urlPath = url.path
	return urlPath.withCString { cstrBuff in
		return tt_execute_check(ptr:cstrBuff)
	}
}

//check if a path is a directory
internal func tt_directory_check(url:URL) -> Bool {
	let urlPath = url.path
	return urlPath.withCString { cstrBuff in
		return tt_directory_check(ptr:cstrBuff)
	}
}

//check if a directory can be accessed
fileprivate func tt_directory_check(ptr:UnsafePointer<Int8>) -> Bool {
	var statInfo = stat()
	guard stat(ptr, &statInfo) == 0, statInfo.st_mode & S_IFMT == S_IFDIR else {
		return false
	}
	guard access(ptr, X_OK) == 0 else {
		return false
	}
	return true
}

//check if a path can be executed
internal func tt_execute_check(ptr:UnsafePointer<Int8>) -> Bool {
	var statInfo = stat()
	guard stat(ptr, &statInfo) == 0, statInfo.st_mode & S_IFMT == S_IFREG else {
		return false
	}
	guard access(ptr, X_OK) == 0 else {
		return false
	}
	return true
}
