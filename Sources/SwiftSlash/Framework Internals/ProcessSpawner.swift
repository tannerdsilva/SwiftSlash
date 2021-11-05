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

internal actor ProcessSpawner {
	enum Error:Swift.Error {
		case badAccess
		case internalError
		case systemForkErrorno(Int32)
		case pipeError
		case resourceUncertainty
	}
		
	internal static let global = ProcessSpawner()
	
	fileprivate let eventTrigger:EventTrigger
	
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
		func handleEvent(_ state:LaunchedProcessState) {
			if let exitContinuation = self.exitContinuation[pid] {
				exitContinuation.resume(returning:state)
			} else {
				self.exitState[pid] = state
			}
		}
		if (WIFSIGNALED(status) == true) {
			handleEvent(.signaled(WTERMSIG(status)))
		} else if (WIFEXITED(status) == true) {
			handleEvent(.exited(WEXITSTATUS(status)))
		}
	}
	
	fileprivate var readerTrigger = [Int32:AsyncStream<Data>.Continuation]()
	fileprivate var largestReadIterations = [Int32:Int]()
	fileprivate var writerTrigger = [Int32:AsyncStream<Int32>.Continuation]()
	fileprivate var writerContinuation = [Int32:AsyncStream<Data>.Continuation]()
	fileprivate init() {
		Task.detached {
			await ChildSignalCatcher.global.add { pid, status in
				await ProcessSpawner.global.handleExit(pid, status)
			}
		}
		self.eventTrigger = EventTrigger.launchNew()
		Task.detached {
			await ProcessSpawner.global._mainLoop()
		}
	}
	fileprivate func _mainLoop() async {
		for await eventDesc in eventTrigger.eventStream {
			self.handleEvent(fh:eventDesc.fh, event:eventDesc.event)
		}
	}
	fileprivate func handleEvent(fh:Int32, event:EventMode) {
		switch event {
			case let .readableEvent(bytes):
				do {
					let getData = try fh.readFileHandle(size:bytes)
					readerTrigger[fh]?.yield(getData)
					if let getReadIterations = largestReadIterations[fh] {
						if getReadIterations < bytes {
							largestReadIterations[fh] = bytes
						}
					} else {
						largestReadIterations[fh] = bytes
					}
				} catch {}
			case .readingClosed:
				var lastData = Data()
				let maxIteration = largestReadIterations.removeValue(forKey:fh) ?? Int(PIPE_BUF)
				do {
					repeat {
						lastData.append(try fh.readFileHandle(size:maxIteration))
					} while true
				} catch {}
				let readTrigger = readerTrigger.removeValue(forKey:fh)
				readTrigger?.yield(lastData)
				readTrigger?.finish()
				fh.closeFileHandle()
				continueWithAvailableResources()
			case .writingClosed:
				writerTrigger.removeValue(forKey:fh)?.finish()
				writerContinuation.removeValue(forKey:fh)?.finish()
				fh.closeFileHandle()
				continueWithAvailableResources()
			case .writableEvent:
				writerTrigger[fh]?.yield(fh)
			break;
		}
		
	}
	
	fileprivate func continueWithAvailableResources() {
		var utilized = Double()
		var limit = Double()
		while getfdlimit(&utilized, &limit) == 0 && (pendingLaunchPackages.count) > 0 && (utilized < floor(0.8 * limit)) {
			let nextItem = self.pendingLaunchPackages.remove(at:0)
			self.launch(package:nextItem)
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
		let exitContinuation:UnsafeContinuation<pid_t, Swift.Error>
	}
	
	fileprivate func launch(package:PackagedLaunch) {
		var fhReadersToDeregisterIfThrown = Set<Int32>()
		var fhWritersToDeregisterIfThrown = Set<Int32>()
		var fhToCloseIfThrown = Set<Int32>()
		var removeReadersFromSelfIfThrown = Set<Int32>()
		var removeWritersFromSelfIfThrown = Set<Int32>()
		do {
			var nullPipes = Set<PosixPipe>()
		
			var enabledWriters = Set<PosixPipe>()
			var writePipes = [Int32:PosixPipe?]()
			var buildOut = [Int32:OutboundChannelState]()
			for curOut in package.writables {
				switch curOut.value.config {
					case .active:
						let newPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:true)
						guard newPipe.isInvalid == false else {
							package.exitContinuation.resume(throwing:FileHandleError.pipeOpenError)
							return
						}
						fhToCloseIfThrown.update(with:newPipe.writing)
						fhToCloseIfThrown.update(with:newPipe.reading)
						writePipes[curOut.key] = newPipe
						try eventTrigger.register(writer:newPipe.writing)
						fhWritersToDeregisterIfThrown.update(with:newPipe.writing)
						enabledWriters.update(with:newPipe)
						let newOut = OutboundChannelState(channel:curOut.value)
						buildOut[curOut.key] = newOut
						_ = self.writerTrigger.updateValue(newOut.continuation, forKey:newPipe.writing)
						_ = self.writerContinuation.updateValue(curOut.value.continuation, forKey:newPipe.writing)
						removeWritersFromSelfIfThrown.update(with:newPipe.writing)
					case .closed:
						writePipes.updateValue(nil, forKey:curOut.key)
					case .nullPipe:
						let newPipe = try PosixPipe.createNullPipe()
						guard newPipe.isInvalid == false else {
							package.exitContinuation.resume(throwing:FileHandleError.pipeOpenError)
							return
						}
						writePipes[curOut.key] = newPipe
						nullPipes.update(with:newPipe)
						fhToCloseIfThrown.update(with:newPipe.writing)
						fhToCloseIfThrown.update(with:newPipe.reading)
				}
			}
			var enabledReaders = Set<PosixPipe>()
			var readPipes = [Int32:PosixPipe?]()
			var buildIn = [Int32:InboundChannelState]()
			for curIn in package.readables {
				switch curIn.value.config {
					case let .active(parseMode):
						let newPipe = try PosixPipe(nonblockingReads:true, nonblockingWrites:true)
						guard newPipe.isInvalid == false else {
							package.exitContinuation.resume(throwing:FileHandleError.pipeOpenError)
							return
						}
						fhToCloseIfThrown.update(with:newPipe.writing)
						fhToCloseIfThrown.update(with:newPipe.reading)
						readPipes[curIn.key] = newPipe
						enabledReaders.update(with:newPipe)
						let newIn = InboundChannelState(mode:parseMode, continuation:curIn.value.continuation)
						buildIn[curIn.key] = newIn
						_ = self.readerTrigger.updateValue(newIn.eventContinuation, forKey:newPipe.reading)
						removeReadersFromSelfIfThrown.update(with:newPipe.reading)
						try eventTrigger.register(reader:newPipe.reading)
						fhReadersToDeregisterIfThrown.update(with:newPipe.reading)
					case .closed:
						readPipes.updateValue(nil, forKey:curIn.key)
					case .nullPipe:
						let newPipe = try PosixPipe.createNullPipe()
						guard newPipe.isInvalid == false else {
							package.exitContinuation.resume(throwing:FileHandleError.pipeOpenError)
							return
						}
						readPipes[curIn.key] = newPipe
						nullPipes.update(with:newPipe)
						fhToCloseIfThrown.update(with:newPipe.writing)
						fhToCloseIfThrown.update(with:newPipe.reading)
				}
			}

			let lpid = try package.path.withCString({ executablePathPointer -> pid_t in
				var argBuild = [package.path]
				argBuild.append(contentsOf:package.args)
				return try argBuild.with_spawn_ready_arguments({ argumentsToSpawn in
					return try package.wd.path.withCString({ workingDirectoryPath in
						return try tt_spawn(path:executablePathPointer, args:argumentsToSpawn, wd:workingDirectoryPath, env:package.env, writePipes:writePipes, readPipes:readPipes)
					})
				})
			})
			
			for writer in enabledWriters {
				writer.reading.closeFileHandle()
			}

			for reader in enabledReaders {
				reader.writing.closeFileHandle()
			}
		
			for pipe in nullPipes {
				pipe.reading.closeFileHandle()
				pipe.writing.closeFileHandle()
			}

			Task.detached { [lpid, buildIn, buildOut, pi = package.interface] in
				await withTaskGroup(of:Void.self, returning:Void.self, body: { tg in
					for curIn in buildIn {
						tg.addTask { [curIn = curIn.value] in
							await withTaskCancellationHandler(handler: {
								curIn.terminateLoop()
							}, operation: {
								await curIn._mainLoop()
							})
						}
					}
					
					for curOut in buildOut {
						tg.addTask { [curOut = curOut.value] in
							await withTaskGroup(of:Void.self, returning:Void.self, body: { outTG in
								await withTaskCancellationHandler(handler: {
									curOut.terminateLoop()
								}, operation: {
									outTG.addTask {
										await curOut._dataLoop()
									}
									outTG.addTask {
										await curOut._eventLoop()
									}
									await outTG.waitForAll()
								})
							})
						}
					}
					let exitResult:LaunchedProcessState = await withUnsafeContinuation { cont in
						tg.addTask {
							await ProcessSpawner.global.registerExitContinuation(pid:lpid, continuation:cont)
						}
					}
					await tg.waitForAll()
					switch exitResult {
						case let .exited(code):
						await pi.stateUpdated(.exited(code))
						case let .signaled(code):
						await pi.stateUpdated(.signaled(code))
					}
				})
			}		
			package.exitContinuation.resume(returning:lpid)
		} catch let error {
			for curClose in fhToCloseIfThrown {
				curClose.closeFileHandle()
			}
			for curDeregister in fhReadersToDeregisterIfThrown {
				try? eventTrigger.deregister(reader:curDeregister)
			}
			for curDeregister in fhWritersToDeregisterIfThrown {
				try? eventTrigger.deregister(writer:curDeregister)
			}
			for curFH in removeReadersFromSelfIfThrown {
				_ = readerTrigger.removeValue(forKey:curFH)
			}
			for curFH in removeWritersFromSelfIfThrown {
				_ = writerTrigger.removeValue(forKey:curFH)
				_ = writerContinuation.removeValue(forKey:curFH)
			}
			package.exitContinuation.resume(throwing:error)
		}
	}
	fileprivate var pendingLaunchPackages = [PackagedLaunch]()
	func launch(path:String, args:[String], wd:URL, env:[String:String], writables:[Int32:DataChannel.Outbound], readables:[Int32:DataChannel.Inbound], taskGroup:inout ThrowingTaskGroup<Void, Swift.Error>, onBehalfOf interface:ProcessInterface) async throws -> pid_t {
		var utilized = Double()
		var limit = Double()
		guard getfdlimit(&utilized, &limit) == 0 else {
			throw Error.resourceUncertainty
		}
		let threshold = floor(0.8 * limit)

		do {
			if utilized > threshold {
				let result:pid_t = try await withUnsafeThrowingContinuation { exitCont in
					self.pendingLaunchPackages.append(PackagedLaunch(interface:interface, path:path, args:args, wd:wd, env:env, writables:writables, readables:readables, exitContinuation:exitCont))
				}
				try await taskGroup.waitForAll()
				return result
			} else {
				let result:pid_t = try await withUnsafeThrowingContinuation { exitCont in
					self.launch(package:PackagedLaunch(interface:interface, path:path, args:args, wd:wd, env:env, writables:writables, readables:readables, exitContinuation:exitCont))
				}
				try await taskGroup.waitForAll()
				return result
			}
		} catch let error {
			taskGroup.cancelAll()
			throw error
		}
	}
}

fileprivate func tt_spawn(path:UnsafePointer<Int8>, args:UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, env:[String:String], writePipes:[Int32:PosixPipe?], readPipes:[Int32:PosixPipe?]) throws -> pid_t {
	//used internally for this function to determine when the forked process has successfully initialized
	let internalNotify = try PosixPipe(nonblockingReads:false, nonblockingWrites:true)
	guard internalNotify.isInvalid == false else {
		throw FileHandleError.pipeOpenError
	}
	
	guard tt_directory_check(ptr:wd) == true && tt_execute_check(ptr:path) == true else {
		throw ProcessSpawner.Error.badAccess
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
				guard reader.value!.isInvalid == false else {
					_ = try? internalNotify.writing.writeFileHandle("1")
					exit(50)
				}
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
				guard writer.value!.isInvalid == false else {
					_ = try? internalNotify.writing.writeFileHandle("1")
					exit(50)
				}
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
		exit(0)
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
