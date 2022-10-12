import Foundation
#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif
import ClibSwiftSlash

//fileprivate func _WSTATUS(_ status:Int32) -> Int32 {
//	return status & 0x7f
//}
//fileprivate func WIFEXITED(_ status:Int32) -> Bool {
//	return _WSTATUS(status) == 0
//}
//fileprivate func WEXITSTATUS(_ status: CInt) -> CInt {
//	return (status >> 8) & 0xff
//}

fileprivate let WCOREFLAG:Int32 = 0200
fileprivate func _WSTATUS(_ x:Int32) -> Int32 {
	return x & 0177
}
fileprivate let _WSTOPPED:Int32 = 0177
fileprivate let _WCONTINUED:Int32 = 0177777
fileprivate func WIFSTOPPED(_ x:Int32) -> Bool {
	return _WSTATUS(x) == _WSTOPPED
}
fileprivate func WSTOPSIG(_ x:Int32) -> Int32 {
	return x >> 8
}
fileprivate func WIFSIGNALED(_ x:Int32) -> Bool {
	return (_WSTATUS(x) != _WSTOPPED && _WSTATUS(x) != 0)
}
fileprivate func WTERMSIG(_ x:Int32) -> Int32 {
	return _WSTATUS(x)
}
fileprivate func WIFEXITED(_ x:Int32) -> Bool {
	return (_WSTATUS(x) == 0)
}
fileprivate func WEXITSTATUS(_ x:Int32) -> Int32 {
	return x >> 8
}
fileprivate func WCOREDUMP(_ x:Int32) -> Int32 {
	return x & WCOREFLAG
}
fileprivate func WIFCONTINUED(_ x:Int32) -> Bool {
	return ((x & _WCONTINUED) == _WCONTINUED)
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

func readPipeline(_ buff:UnsafePointer<UInt8>, _ buffSize:size_t, _ isClosed:Bool, _ usrPtr:UnsafeMutableRawPointer?) {
	let dci:DataChannel.Inbound?
	if (usrPtr == nil) {
		dci = nil
	} else {
		if (isClosed == false) {
			dci = Unmanaged<DataChannel.Inbound>.fromOpaque(usrPtr!).takeUnretainedValue()
		} else {
			dci = Unmanaged<DataChannel.Inbound>.fromOpaque(usrPtr!).takeRetainedValue()
		}
	}
	
	if isClosed == false {
		if let hasDCI = dci {
			let createData = Data(bytes:buff, count:buffSize);
			let asString = String(data:createData, encoding:.utf8)
			hasDCI.continuation.yield(createData)
		} else {
			print("r item- noDCI \(buffSize)")
		}
	} else {
		if let hasDCI = dci {
			hasDCI.continuation.finish()
		}
	}
	
	/*
	if let hasUserPointer = usrPtr?.assumingMemoryBound(to:DataChannel.Inbound.self) {
		
		hasUserPointer.pointee.continuation.yield(createData);
		if (isClosed == true) {
			let um = Unmanaged<DataChannel.Inbound>.fromOpaque(hasUserPointer).takeRetainedValue()
			um.continuation.finish()
		}
	}*/
}

func writePipeline(_ isClosed:Bool, _ usrPtr:UnsafeMutableRawPointer?) {
	
}

internal actor ProcessSpawner {
	enum Error:Swift.Error {
		case workingDirectory_badAccess
		case executable_badAccess
		case internalError
		case systemForkErrorno(Int32)
		case pipeError
		case resourceUncertainty
		case pathNotExecutable(String)
		
		case eventTriggerRegistrationError(Int32)
	}
		
	internal static let global = ProcessSpawner()
	
	enum LaunchedProcessState {
		case exited(Int32)
		case signaled(Int32)
	}

	
	fileprivate var exitState = [pid_t:LaunchedProcessState]()
	fileprivate var exitContinuation = [pid_t:UnsafeContinuation<LaunchedProcessState, Never>]()
	fileprivate func registerExitContinuation(pid:pid_t, continuation:UnsafeContinuation<LaunchedProcessState, Never>) {
		if let pidExit = self.exitState[pid] {
			continuation.resume(returning:pidExit)
		} else {
			self.exitContinuation[pid] = continuation
		}
	}
	fileprivate func handleExit(_ pid:pid_t, _ status:Int32) {
		if (WIFSIGNALED(status) == true) {
			lc_signal(pid, WTERMSIG(status))
		} else if (WIFEXITED(status) == true) {
			lc_exit(pid, WEXITSTATUS(status))
		}
	}
	
	
	fileprivate let globalET = et_alloc();
	fileprivate init() {
		lc_init();
		et_init(globalET, readPipeline, writePipeline);
		Task.detached {
			await ChildSignalCatcher.global.add { pid, status in
				await ProcessSpawner.global.handleExit(pid, status)
			}
		}
	}
	
	fileprivate struct PackagedLaunch {
		let interface:ProcessInterface
		let path:String
		let args:[String]
		let wd:URL
		let env:[String:String]
		let writables:[Int32:DataChannel.Outbound]
		let readables:[Int32:DataChannel.Inbound]
//		let exitContinuation:UnsafeContinuation<pid_t, Swift.Error>
	}
	
	internal func launch(path:String, args:[String], wd:URL, env:[String:String], writables:[Int32:DataChannel.Outbound], readables:[Int32:DataChannel.Inbound], onBehalfOf pi:ProcessInterface) throws -> pid_t {
		// needs to be released this function throws
		let retainedPI = Unmanaged<ProcessInterface>.passRetained(pi).toOpaque()

		let newTG = tg_init(retainedPI, { retPI, pid, stat, code in
			let pi = Unmanaged<ProcessInterface>.fromOpaque(retPI!).takeRetainedValue()
			Task.detached {
				try await pi.processExited(code: code)
			}
			
		})
		
		var fhToCloseIfThrown = Set<Int32>()
		var registeredReaders = Set<readerinfo_ptr_t>()
		var registeredWriters = Set<writerinfo_ptr_t>()
		do {
			var nullPipes = Set<PosixPipe>()
			
			// build the written streams
			var enabledWriters = Set<PosixPipe>()
			var writePipes = [Int32:PosixPipe?]()
			for curOut in writables {
				switch curOut.value.config {
					case .active:
						let newPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:true);
						fhToCloseIfThrown.update(with:newPipe.reading)
						fhToCloseIfThrown.update(with:newPipe.writing)
						writePipes[curOut.key] = newPipe
					
						// install the termination group on the writer info
						wi_assign_tg(curOut.value.wi, newTG);
					
						let regResult = et_w_register(globalET, newPipe.writing, nil, curOut.value.wi)
						guard (regResult == 0) else {
							throw Error.eventTriggerRegistrationError(regResult)
						}
						registeredWriters.update(with:curOut.value.wi)
						enabledWriters.update(with:newPipe)
					
					case .closed:
						writePipes.updateValue(nil, forKey:curOut.key)
					case .nullPipe:
						let newPipe = try PosixPipe.createNullPipe()
						fhToCloseIfThrown.update(with:newPipe.writing)
						fhToCloseIfThrown.update(with:newPipe.reading)
						writePipes[curOut.key] = newPipe
						nullPipes.update(with:newPipe)
				}
			}
			
			// build the reading streams
			var enabledReaders = Set<PosixPipe>()
			var readPipes = [Int32:PosixPipe?]()
			for curIn in readables {
				switch curIn.value.config {
					case let .active(parseMode):
						let newPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:true)
						fhToCloseIfThrown.update(with:newPipe.writing)
						fhToCloseIfThrown.update(with:newPipe.reading)
						readPipes[curIn.key] = newPipe
					
						// install the termination group on the reader info
						ri_assign_tg(curIn.value.ri, newTG);
					
						// retain the inbound data channel so that its continuation can be referenced
						let retainedRI = Unmanaged.passRetained(curIn.value)
						let asOpaque = retainedRI.toOpaque()
						
						let regResult = parseMode.dataRepresentation().withUnsafeBytes { byteBuff in
							return et_r_register(globalET, newPipe.reading, byteBuff.baseAddress!.assumingMemoryBound(to:UInt8.self), UInt8(byteBuff.count), asOpaque, curIn.value.ri)
						}
						
						guard regResult == 0 else { 
							throw Error.eventTriggerRegistrationError(regResult)
						}
					
						registeredReaders.update(with:curIn.value.ri);
						enabledReaders.update(with:newPipe)
					

					case .closed:
						readPipes.updateValue(nil, forKey:curIn.key)
					case .nullPipe:
						let newPipe = try PosixPipe.createNullPipe()
						readPipes[curIn.key] = newPipe
						nullPipes.update(with:newPipe)
						fhToCloseIfThrown.update(with:newPipe.writing)
						fhToCloseIfThrown.update(with:newPipe.reading)
				}
			}
			
			let lpid = try path.withCString({ executablePathPointer -> pid_t in
				var argBuild = [path]
				argBuild.append(contentsOf:args)
				return try argBuild.with_spawn_ready_arguments({ argumentsToSpawn in
					return try wd.path.withCString({ workingDirectoryPath in
						return try tt_spawn(path:executablePathPointer, args:argumentsToSpawn, wd:workingDirectoryPath, env:env, writePipes:writePipes, readPipes:readPipes, terminationGroup:newTG)
					})
				})
			})
			
			for writer in enabledWriters {
				close(writer.reading);
			}
			
			for reader in enabledReaders {
				close(reader.writing);
			}
			
			for np in nullPipes {
				close(np.writing);
				close(np.reading);
			}
			
			return lpid;
		} catch let error {
			_ = Unmanaged<ProcessInterface>.fromOpaque(retainedPI).takeRetainedValue()
			
			for wiDereg in registeredWriters {
//				et_w_deregister(globalET, wiDereg);
			}
			
			for riDereg in registeredReaders {
//				et_r_deregister(globalET, riDereg);
			}
			throw error
		}
	}
}

//fileprivate func launch(package:PackagedLaunch) throws -> pid_t {
//		var fhToCloseIfThrown = Set<Int32>();
//		var registeredReaders = Set<readerinfo_ptr_t>()
//		var registeredWriters = Set<writerinfo_ptr_t>()
//		do {
//			var nullPipes = Set<PosixPipe>()
//
//			var enabledWriters = Set<PosixPipe>()
//			var writePipes = [Int32:PosixPipe?]()
//			for curOut in package.writables {
//				switch curOut.value.config {
//				case .active:
//					let newPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:true);
//					fhToCloseIfThrown.update(with:newPipe.reading)
//					fhToCloseIfThrown.update(with:newPipe.writing)
//					writePipes[curOut.key] = newPipe
//
//					let regResult = et_w_register(globalET, newPipe.writing, nil, curOut.value.wi)
//					guard (regResult == 0) else {
//						throw Error.eventTriggerRegistrationError(regResult)
//					}
//					registeredWriters.update(with:curOut.value.wi);
//					enabledWriters.update(with:newPipe)
//				case .closed:
//					writePipes.updateValue(nil, forKey:curOut.key)
//				case .nullPipe:
//					let newPipe = try PosixPipe.createNullPipe()
//					fhToCloseIfThrown.update(with:newPipe.writing)
//					fhToCloseIfThrown.update(with:newPipe.reading)
//					writePipes[curOut.key] = newPipe
//					nullPipes.update(with:newPipe)
//				}
//			}
//
//			var enabledReaders = Set<PosixPipe>()
//			var readPipes = [Int32:PosixPipe?]()
//			for curIn in package.readables {
//				switch curIn.value.config {
//					case let .active(parseMode):
//						let newPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:true)
//						fhToCloseIfThrown.update(with:newPipe.writing)
//						fhToCloseIfThrown.update(with:newPipe.reading)
//						readPipes[curIn.key] = newPipe
//						enabledReaders.update(with:newPipe)
//
//						let retainedRI = Unmanaged.passRetained(curIn.value)
//						let asOpaque = retainedRI.toOpaque()
//
//						let regResult = parseMode.dataRepresentation().withUnsafeBytes { byteBuff in
//							return et_r_register(globalET, newPipe.reading, byteBuff.baseAddress!.assumingMemoryBound(to: UInt8.self), UInt8(byteBuff.count), asOpaque, curIn.value.ri);
//						}
//						guard regResult == 0 else {
//							throw Error.eventTriggerRegistrationError(regResult)
//						}
//
//					case .closed:
//						readPipes.updateValue(nil, forKey:curIn.key)
//					case .nullPipe:
//						let newPipe = try PosixPipe.createNullPipe()
//						readPipes[curIn.key] = newPipe
//						nullPipes.update(with:newPipe)
//						fhToCloseIfThrown.update(with:newPipe.writing)
//						fhToCloseIfThrown.update(with:newPipe.reading)
//				}
//			}
//
//			let lpid = try package.path.withCString({ executablePathPointer -> pid_t in
//				var argBuild = [package.path]
//				argBuild.append(contentsOf:package.args)
//				return try argBuild.with_spawn_ready_arguments({ argumentsToSpawn in
//					return try package.wd.path.withCString({ workingDirectoryPath in
//						return try tt_spawn(path:executablePathPointer, args:argumentsToSpawn, wd:workingDirectoryPath, env:package.env, writePipes:writePipes, readPipes:readPipes, terminationGroup: <#terminationgroup_ptr_t#>)
//					})
//				})
//			})
//
//
//
//			for writer in enabledWriters {
//				writer.reading.closeFileHandle()
//			}
//
//			for reader in enabledReaders {
//				reader.writing.closeFileHandle()
//			}
//
//			for pipe in nullPipes {
//				pipe.reading.closeFileHandle()
//				pipe.writing.closeFileHandle()
//			}
//			return lpid;
//		}
//	}
//
//	fileprivate var pendingLaunchPackages = [PackagedLaunch]()
//	func launch(path:String, args:[String], wd:URL?, env:[String:String], writables:[Int32:DataChannel.Outbound], readables:[Int32:DataChannel.Inbound], onBehalfOf interface:ProcessInterface) async throws -> pid_t {
//		return try await self.launch(package:PackagedLaunch(interface:interface, path:path, args:args, wd:wd ?? URL(fileURLWithPath:String(cString:getpwuid(getuid())!.pointee.pw_dir)), env:env, writables:writables, readables:readables))
//	}


// after calling this function, the passed terminationgroup will either be in a launched or aborted state. if the function throws, the terminationgroup will the aborted. if the function returns, the terminationgroup will be launched.
fileprivate func tt_spawn(path:UnsafePointer<Int8>, args:UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, env:[String:String], writePipes:[Int32:PosixPipe?], readPipes:[Int32:PosixPipe?], terminationGroup tg:terminationgroup_ptr_t) throws -> pid_t {
	do {
		// used internally for this function to determine when the forked process has successfully initialized
		let internalNotify = try PosixPipe(nonblockingReads:false, nonblockingWrites:true)

		// check that the working directory is accessible
		guard tt_directory_check(ptr:wd) == true else {
			throw ProcessSpawner.Error.workingDirectory_badAccess
		}
		
		// check that the executable is accessible
		guard tt_execute_check(ptr: path) == true else {
			throw ProcessSpawner.Error.pathNotExecutable(String(cString:path))
		}
		
		let forkResult = cfork()	//spawn the container process
		
		func prepareLaunch() -> Never {
			//close the reading end of the internal pipe immediately
			internalNotify.reading.closeFileHandle()
			
			//change working directory
			guard chdir(wd) == 0 else {
				_ = try? internalNotify.writing.writeFileHandle("1")
				exit(50)
			}
			
			//clear the environment variables
			guard CurrentProcessState.clearEnvironmentVariables() == 0 else {
				_ = try? internalNotify.writing.writeFileHandle("1")
				exit(50)
			}

			//assign the new environment variables
			for kv in env {
				kv.key.withCString { keyPointer in
					kv.value.withCString { valuePointer in
						guard setenv(keyPointer, valuePointer, 1) == 0 else {
							_ = try? internalNotify.writing.writeFileHandle("1")
							exit(50)
						}
					}
				}
			}
					
			//assign the writing pipes and reading pipes
			for reader in readPipes {
				if (reader.value != nil) {
					guard dup2(reader.value!.writing, reader.key) >= 0 else {
						_ = try? internalNotify.writing.writeFileHandle("1")
						exit(50)
					}
					close(reader.value!.writing)
					close(reader.value!.reading)
				}
			}
			for writer in writePipes {
				if (writer.value != nil) {
					guard dup2(writer.value!.reading, writer.key) >= 0 else {
						_ = try? internalNotify.writing.writeFileHandle("1")
						exit(50)
					}
					close(writer.value!.writing)
					close(writer.value!.reading)
				}
			}
			
	#if os(Linux)
			let fdPath = "/proc/self/fd"
	#elseif os(macOS)
			let fdPath = "/dev/fd"
	#endif
			
			//close any extra file handles
			guard let openFileHandlesPointer = opendir(fdPath) else {
				_ = try? internalNotify.writing.writeFileHandle("1")
				exit(50)
			}
			while let curPointer = readdir(openFileHandlesPointer) {
				withUnsafePointer(to:&curPointer.pointee.d_name) { pointer in
					let buffer = UnsafeRawPointer(pointer).assumingMemoryBound(to:Int8.self)
					let length = strlen(buffer)
					let data = Data(bytes:buffer, count:length)
					if data.contains(46) == false {
						let curFh = atoi(buffer)
						if writePipes[curFh] == nil && readPipes[curFh] == nil && curFh != internalNotify.writing {
							close(curFh)
						}
					}
				}
			}
			closedir(openFileHandlesPointer)
			_ = try! internalNotify.writing.writeFileHandle("0")
			internalNotify.writing.closeFileHandle()
			#if os(Linux)
			Glibc.execvp(path, args)
			#elseif os(macOS)
			Darwin.execvp(path, args)
			#endif
			exit(66)
		}
		switch forkResult {
			case -1:
				//in parent, error
				throw ProcessSpawner.Error.systemForkErrorno(errno)
			case 0:
				//in child: success
				prepareLaunch()
			default:
				//in parent, success
				
				//close the writing end of the internal notify pipe
				internalNotify.writing.closeFileHandle()
			
				// wait for the child process to send us some data
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
					} catch {
						shouldLoop = false
					}
				} while shouldLoop == true
				
				// close the file handle we are reading from
				internalNotify.reading.closeFileHandle()
			
				guard triggerData.count > 0 else {
					throw ProcessSpawner.Error.internalError
				}
				guard let notifyString = String(data:triggerData, encoding:.utf8) else {
					throw ProcessSpawner.Error.internalError
				}
				guard notifyString == "0" else {
					throw ProcessSpawner.Error.internalError
				}
				// update the termination group with the pid
				guard tg_launch(tg, forkResult) == 0 else {
					throw ProcessSpawner.Error.internalError
				}
				// store the termination group in the lifecycle store
				guard lc_launch(tg) == 0 else {
					throw ProcessSpawner.Error.internalError
				}
				
				return forkResult
		}
	} catch let error {
		tg_abort(tg);
		throw error
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
