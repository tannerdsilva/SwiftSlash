import Foundation
import Glibc
fileprivate func _WSTATUS(_ status:Int32) -> Int32 {
    return status & 0x7f
}
fileprivate func WIFEXITED(_ status:Int32) -> Bool {
    return _WSTATUS(status) == 0
}
fileprivate func WIFSIGNALED(_ status:Int32) -> Bool {
    return (_WSTATUS(status) != 0) && (_WSTATUS(status) != 0x7f)
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

//waits for a process to exit
internal func tt_wait_sync(pid:pid_t) -> Int32 {
    var waitResult:Int32 = 0
    var exitCode:Int32 = 0
    var errNo:Int32 = 0
    repeat {
        waitResult = waitpid(pid, &exitCode, 0)
        errNo = errno
    } while waitResult == -1 && errNo == EINTR
    return WEXITSTATUS(exitCode)
}

//this is the structure that is used to capture all relevant information about a process that is in flight
internal struct tt_proc_signature:Hashable {
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
    static func == (lhs:tt_proc_signature, rhs:tt_proc_signature) -> Bool {
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

//this is the wrapping function for tt_spawn. this function can be used with swift objects rather than c pointers that are required for the base tt_spawn command
//before calling the base `tt_spawn` command, this function will prepare the global pipe readers for any spawns that are configured for stdout and stderr capture
internal typealias TTSpawnReadingHandler = InboundDataHandler?
internal typealias TTSpawnTerminationHandler = (Int32) -> Void
internal let serial_spawn = DispatchQueue(label:"com.swiftslash.function.tt_spawn", target:process_master_queue)
internal func tt_spawn(path:String, args:[String], wd:URL, env:[String:String], stdout:InboundDataHandler?, stdoutParseMode:DataParseMode, stderrParseMode:DataParseMode, stderr:InboundDataHandler?, exitHandler:@escaping(TTSpawnTerminationHandler)) throws -> tt_proc_signature {
	return try serial_spawn.sync {
		let stdoutPipe:PosixPipe
		let stderrPipe:PosixPipe
		let stdinPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:true)

		let terminationGroup = TerminationGroup(fhs:Set<Int32>([stdinPipe.writing]), terminationHandler: { [exitHandler] exitPid in
			exitHandler(tt_wait_sync(pid:exitPid))
		})

		let writeConfig = WritableConfiguration(fh:stdinPipe.writing, group:terminationGroup)
		var readConfigs = [ReadableConfiguration]()

		//configure for a standard output handler if the user passed a handler block
		if stdout != nil {
			stdoutPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:true)
			terminationGroup.include(fh:stdoutPipe.reading)
			readConfigs.append(ReadableConfiguration(fh:stdoutPipe.reading, parseMode:stdoutParseMode, group:terminationGroup, handler:stdout!))
			guard stdoutPipe.isNullValued == false else {
				throw tt_spawn_error.pipeError
			}
		} else {
			stdoutPipe = PosixPipe(reading:-1, writing:-1)
		}

		//configure for a standard error handler if the user passed a handler block
		if stderr != nil {
			stderrPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:true)
			terminationGroup.include(fh:stderrPipe.reading)
			readConfigs.append(ReadableConfiguration(fh:stderrPipe.reading, parseMode:stderrParseMode, group:terminationGroup, handler:stderr!))
			guard stderrPipe.isNullValued == false else {
				throw tt_spawn_error.pipeError
			}
		} else {
			stderrPipe = PosixPipe(reading:-1, writing:-1)
		}

		//bind the standard input handler. this is always configured because it is our primary means of determining when a process exits
		guard stdinPipe.reading != -1 && stdinPipe.writing != -1 else {
			throw tt_spawn_error.pipeError
		}

		let stdinChannel = try EventSwarm.global.register(readers:readConfigs, writer:writeConfig)
	
		//launch the process
		let returnVal = try path.withCString({ executablePathPointer -> pid_t in
			var argBuild = [path]
			argBuild.append(contentsOf:args)
			return try argBuild.with_spawn_ready_arguments({ argumentsToSpawn in
				return try wd.path.withCString({ workingDirectoryPath in
					return try tt_spawn(path:executablePathPointer, args:argumentsToSpawn, wd:workingDirectoryPath, env:env, stdin:stdinPipe, stdout:stdoutPipe, stderr:stderrPipe)
				})
			})
		})

		terminationGroup.setAssociatedPid(returnVal)

		return tt_proc_signature(work:returnVal, stdin:stdinPipe, stdout:stdoutPipe, stderr:stderrPipe, stdinChannel:stdinChannel)
	}
}

internal enum tt_spawn_error:Error {
    case badAccess
    case internalError
    case systemForkErrorno(Int32)
    case pipeError
}
//spawns two processes. first process is responsible for executing the actual command. second process is responsible for watching the executing process, and notifying the parent about the status of the executing process. This "monitor process" is also responsible for closing the standard inputs and outputs so that they do not get mixed in with the parents standard file descriptors
//the primary means of I/O for the monitor process is the file descriptor passed to this function `notify`. This file descriptor acts as the activity log for the monitor process.
//three types of monitor process events, launch event, exit event, and fatal event
//BEHAVIOR UNDEFINED if a null valued standard input pipe is passed to this function
fileprivate func tt_spawn(path:UnsafePointer<Int8>, args:UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, env:[String:String], stdin:PosixPipe, stdout:PosixPipe, stderr:PosixPipe) throws -> pid_t {
    //used internally for this function to determine when the forked process has successfully initialized
    let internalNotify = try PosixPipe(nonblockingReads:false, nonblockingWrites:true)
	guard internalNotify.isNullValued == false else {
		throw tt_spawn_error.pipeError
	}
	
	guard tt_directory_check(ptr:wd) == true && tt_execute_check(ptr:path) == true else {
		throw tt_spawn_error.badAccess
	}
	
    let forkResult = fork()	//spawn the container process
    		
    func processMonitor() -> Never {
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
            throw tt_spawn_error.systemForkErrorno(errno)
        case 0:
            //in child: success
            processMonitor()
        
        default:
            //in parent, success
            
            //configure the file handles for the context of the parent process synchronously
            file_handle_guard.sync {
				close(internalNotify.writing)
            	close(stdin.reading)
            	close(stderr.writing)
            	close(stdout.writing)
            }
			
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
            file_handle_guard.async { [closeHandle = internalNotify.reading] in
            	close(closeHandle)
            }
            
            //parse the data that was received in the internalNotify pipe
            guard triggerData.count > 0 else {
            	throw tt_spawn_error.internalError
            }
            guard let notifyString = String(data:triggerData, encoding:.utf8) else {
            	throw tt_spawn_error.internalError
            }
            guard notifyString == "0" else {
				throw tt_spawn_error.internalError
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
