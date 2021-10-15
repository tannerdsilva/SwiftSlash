import Foundation

//these are the types of line breaks that can be parsed from incoming data channels
public enum DataParseMode:UInt8 {
	case cr			//parses line breaks with the cr byte
	case lf			//parses line breaks with the lf byte
	case crlf		//parses line breaks with the sequence of cr + lf
	case immediate	//does not parse line breaks, fires the data handler as soon as the data is available
	case discard	//do not handle data for this channel
}

public actor ProcessInterface {
	public enum Error:Swift.Error {
		case invalidProcessState
		case abnormalExit
	}
	
	public enum Status:UInt8 {
		case initialized
		case running
		case signaled
		case exited
		case failed
	}
	public var status:Status = .initialized
	
//	public typealias ExitHandler = (Int32?, ProcessInterface) -> Void

	//stdout streams
	public let stdoutParseMode:DataParseMode
	public var stdout:AsyncStream<Data>?
	fileprivate let stdoutContinuation:AsyncStream<Data>.Continuation?
	
	//stderr streams
	public let stderrParseMode:DataParseMode
	public var stderr:AsyncStream<Data>?
	fileprivate let stderrContinuation:AsyncStream<Data>.Continuation?
	
	public let command:Command
	fileprivate var signature:ProcessSignature? = nil
	
	init(command:Command, stdoutParseMode:DataParseMode = .lf, stderrParseMode:DataParseMode = .lf) throws {
		var outContinuation:AsyncStream<Data>.Continuation? = nil
		self.stdoutParseMode = stdoutParseMode
		if stdoutParseMode != .discard {
			self.stdout = AsyncStream(Data.self) { stdoutContinuation in
				outContinuation = stdoutContinuation
			}
		} else {
			self.stdout = nil
		}
		self.stdoutContinuation = outContinuation
		
		var errContinuation:AsyncStream<Data>.Continuation? = nil
		self.stderrParseMode = stderrParseMode
		if stderrParseMode != .discard {
			self.stderr = AsyncStream(Data.self) { stderrContinuation in
				errContinuation = stderrContinuation
			}
		} else {
			self.stderr = nil
		}
		self.stderrContinuation = errContinuation
		self.command = command
	}
	
	public func launch() async throws {
		self.signature = try await ProcessSpawner.global.launch(path:self.command.executable, args:self.command.arguments, wd:self.command.workingDirectory, env:self.command.environment, stdout:stdoutContinuation, stdoutParseMode:self.stdoutParseMode, stderr:stderrContinuation, stderrParseMode:self.stderrParseMode)
	}
	
	public func exitCode() async throws -> Int32 {
		let tg = self.signature!.stdinChannel.terminationGroup
		let exitStatus = await tg.getExitStatus()
		if exitStatus.didExit {
			if exitStatus.exitCode != nil {
				return exitStatus.exitCode!
			} else {
				throw Error.abnormalExit
			}
		} else {
			return try await withUnsafeThrowingContinuation { [tg] continuation in
				Task.detached { [tg, continuation] in
					await tg.whenExited({ exitCode in
						if (exitCode != nil) {
							continuation.resume(returning:exitCode!)
						} else {
							continuation.resume(throwing:Error.abnormalExit)
						}
					})
				}
			}
		}
	}
}

	
//	@discardableResult public func run() async throws -> Int32? {
//		var myContinuation:UnsafeContinuation<Int32?, Swift.Error>? = nil
//		await withUnsafeThrowingContinuation { exitContinuation in
//			myContinuation = exitContinuation
//		}
//
//		guard self.status == .initialized else {
//			exitContinuation.resume(throwing:Error.invalidProcessState)
//		}
//	
//		//build the stdout handler function that is going to be passed to the process spawner
//		let outHandler:InboundDataHandler?
//		if let outContinuation = stdoutContinuation {
//			outHandler = { someData in
//				if someData == nil {
//					outContinuation.finish()
//				} else {
//					outContinuation.yield(someData!)
//				}
//			}		
//		} else {
//			outHandler = nil
//		}
//	
//		//build the stderr handler function that is going to be passed to the process spawner
//		let errHandler:InboundDataHandler?
//		if let errContinuation = stderrContinuation {
//			errHandler = { someData in
//				if someData == nil {
//					errContinuation.finish()
//				} else {
//					errContinuation.yield(someData!)
//				}
//			} 
//		} else {
//			errHandler = nil
//		}
//		do {
//		self.signature = try await ProcessSpawner.global.launch(path:self.command.executable, args:self.command.arguments, wd:self.command.workingDirectory, env:self.command.environment, stdout:outHandler, stdoutParseMode:self.stdoutParseMode, stderr:errHandler, stderrParseMode:self.stderrParseMode, exitHandler: { exitCode in
//			Task.detached {
//				print("WOW")
//			}
//		})
//			self.status = .running
//		} catch let error {
//			self.status = .failed
//			throw error
//		}
//	}
//}

//public actor ProcessInterface {
//	public enum Error:Swift.Error {
//		case invalidProcessState
//		case processSignaled
//	}
//	
//	public enum Status:UInt8 {
//		case initialized
//		case running
//		case signaled
//		case exited
//		case failed
//	}
//	public var status:Status = .initialized
//	
//	public typealias DataHandler = (Data, ProcessInterface) -> Void
//	public typealias ExitHandler = (Int32?, ProcessInterface) -> Void
//	
//	//handlers
//	//stdout
//	public var stdoutParseMode:DataParseMode = .lf
//	public var stdoutHandler:DataHandler? = nil
//	
//	//stderr
//	public var stderrParseMode:DataParseMode = .lf
//	public var stderrHandler:DataHandler? = nil
//	
//	//exit
//	public var exitHandler:ExitHandler? = nil
//	
//	//launch parameters
//	public var command:Command
//	public var workingDirectory:URL = CurrentProcessState.getCurrentWorkingDirectory()
//	public var exitCode:Int32? = nil
//	
//	internal var signature:ProcessSignature? = nil
//	
//	public init(command:Command) {
//		self.command = command
//	}
//	
//	fileprivate func processExited(_ code:Int32?) -> ExitHandler? {
//		if code == nil {
//			self.status = .signaled
//		} else {
//			self.status = .exited
//		}
//		return self.exitHandler
//	}	
//	
//	@discardableResult public func run() async throws -> pid_t {
//		guard self.status == .initialized else {
//			throw Error.invalidProcessState
//		}
//		let outGateway:InboundDataHandler?
//		if (self.stdoutHandler == nil) {
//			outGateway = nil
//		} else {
//			outGateway = { [dh = self.stdoutHandler!] someData in
//				dh(someData, self)
//			}
//		}
//		
//		let errGateway:InboundDataHandler?
//		if (self.stderrHandler == nil) {
//			errGateway = nil
//		} else {
//			errGateway = { [dh = self.stderrHandler!] someData in
//				dh(someData, self)
//			}
//		}
//		do {
//			self.signature = try await ProcessSpawner.global.launch(path:self.command.executable, args:self.command.arguments, wd:self.workingDirectory, env:self.command.environment, stdout:outGateway, stdoutParseMode:stdoutParseMode, stderr:errGateway, stderrParseMode:stderrParseMode, exitHandler: { exitCode in
//				Task.detached {
//					if let externalExitHandler = await self.processExited(exitCode) {
//						externalExitHandler(exitCode, self)
//					}
//				}
//			})
//			self.status = .running
//			return self.signature!.worker
//		} catch let error {
//			self.status = .failed
//			throw error
//		}
//	}
//	
//	public func write(stdin:Data) async throws {
//		guard self.status == .running else {
//			throw Error.invalidProcessState
//		}
//		await self.signature!.stdinChannel.broadcast(stdin)
//	}
//}
