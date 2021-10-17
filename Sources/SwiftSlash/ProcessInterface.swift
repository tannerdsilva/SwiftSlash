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

	//stdout streams
	public let stdoutParseMode:DataParseMode
	public var stdout:AsyncStream<Data>
	fileprivate let stdoutContinuation:AsyncStream<Data>.Continuation?
	
	//stderr streams
	public let stderrParseMode:DataParseMode
	public var stderr:AsyncStream<Data>
	fileprivate let stderrContinuation:AsyncStream<Data>.Continuation?
	
	public let command:Command
	fileprivate var signature:ProcessSignature? = nil
	
	public init(command:Command, stdoutParseMode:DataParseMode = .lf, stderrParseMode:DataParseMode = .lf) {
		var outContinuation:AsyncStream<Data>.Continuation? = nil
		self.stdoutParseMode = stdoutParseMode
		let out = AsyncStream(Data.self) { stdoutContinuation in
			outContinuation = stdoutContinuation
		}
		self.stdout = out
		if stdoutParseMode == .discard {
			self.stdoutContinuation = nil
			outContinuation!.finish()
		} else {
			self.stdoutContinuation = outContinuation
		}
		
		var errContinuation:AsyncStream<Data>.Continuation? = nil
		self.stderrParseMode = stderrParseMode
		let err = AsyncStream(Data.self) { stderrContinuation in
			errContinuation = stderrContinuation
		}
		self.stderr = err
		if stderrParseMode == .discard {
			self.stderrContinuation = nil
			errContinuation!.finish()
		} else {
			self.stderrContinuation = errContinuation
		}

		self.command = command
	}
	
	@discardableResult public func launch() async throws -> (stdout:AsyncStream<Data>, stderr:AsyncStream<Data>) {
		guard self.status == .initialized else {
			throw Error.invalidProcessState
		}
		self.status = .running
		do {
			self.signature = try await ProcessSpawner.global.launch(path:self.command.executable, args:self.command.arguments, wd:self.command.workingDirectory, env:self.command.environment, stdout:stdoutContinuation, stdoutParseMode:self.stdoutParseMode, stderr:stderrContinuation, stderrParseMode:self.stderrParseMode)
			await self.signature!.stdinChannel.terminationGroup.setOwningProcess(self)
			return (stdout:self.stdout, stderr:self.stderr)
		} catch let error {
			self.status = .failed
			throw error
		}
	}
	
	public func exitCode() async throws -> Int32 {
		if self.status == .initialized {
			try await self.launch()
		}
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
