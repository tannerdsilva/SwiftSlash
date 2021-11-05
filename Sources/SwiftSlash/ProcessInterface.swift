import Foundation

public actor ProcessInterface {
	public enum Error:Swift.Error {
		case invalidProcessState
		case processSignaled
		case signalError
	}
	
	internal var _state:State = .initialized
	public var state:State {
		get {
			return _state
		}
	}
	internal func stateUpdated(_ newState:State) {
		_state = newState
		switch newState {
			case .exited:
				for curItem in self.exitStack {
					curItem(self.state)
				}
				self.exitStack.removeAll(keepingCapacity:false)

			case .signaled:
				for curItem in self.exitStack {
					curItem(self.state)
				}
				self.exitStack.removeAll(keepingCapacity:false)
			default:
			break;
		}
	}
	public enum State:Equatable {
		case initialized
		case launching
		case running(pid_t)
		case paused
		case signaled(Int32)
		case exited(Int32)
		case failed
		
		public static func == (lhs:State, rhs:State) -> Bool {
			switch lhs {
				case .initialized:
					switch rhs {
						case .initialized:
							return true
						default:
							return false
					}
				case .launching:
					switch rhs {
						case .launching:
							return true
						default:
							return false
					}
				case let .running(pid_t_l):
					switch rhs {
						case let .running(pid_t_r):
							return pid_t_l == pid_t_r
						default:
							return false
					}
				case .paused:
					switch rhs {
						case .paused:
							return true
						default:
							return false
					}
				case let .signaled(lcode):
					switch rhs {
						case let .signaled(rcode):
							return lcode == rcode
						default:
							return false
					}
				case let .exited(lcode):
					switch rhs {
						case let .exited(rcode):
							return lcode == rcode
						default:
							return false
					}
				case .failed:
					switch rhs {
						case .failed:
							return true
						default:
							return false
					}
			}
		}
	}
	
	
	//outbound writable channels
	public var outboundChannels:[Int32:DataChannel.Outbound]

	//inbound readable channels
	public var inboundChannels:[Int32:DataChannel.Inbound]
	public var stdout:AsyncStream<Data> {
		get {
			guard let captureChannel = inboundChannels[STDOUT_FILENO] else {
				fatalError("do not use the stdout convenience property for channels that have not been configured")
			}
			return captureChannel.stream
		}
	}
	public var stderr:AsyncStream<Data> {
		get {
			guard let captureChannel = inboundChannels[STDERR_FILENO] else {
				fatalError("do not use the stderr convenience property for channels that have not been configured ")
			}
			return captureChannel.stream
		}
	}
	public let command:Command
		
	public init(command:Command, stdin:DataChannel.Outbound.Configuration = .active, stdout:DataChannel.Inbound.Configuration = .active(.lf), stderr:DataChannel.Inbound.Configuration = .active(.lf)) {
		self.command = command
		//create channels for STDOUT and STDERR
		self.inboundChannels = [
			STDOUT_FILENO: DataChannel.Inbound(target:STDOUT_FILENO, config:stdout),
			STDERR_FILENO: DataChannel.Inbound(target:STDERR_FILENO, config:stderr)
		]
		//create a channel for STDIN
		self.outboundChannels = [
			STDIN_FILENO: DataChannel.Outbound(target:STDIN_FILENO)
		]
	}
		
	public func launch() async throws {
		guard case self._state = State.initialized else {
			throw Error.invalidProcessState
		}
		self._state = .launching
		do {
			let exitPid = try await withThrowingTaskGroup(of:Void.self, returning:pid_t.self, body: { tg in
				try await ProcessSpawner.global.launch(path:self.command.executable, args:self.command.arguments, wd:self.command.workingDirectory, env:self.command.environment, writables:self.outboundChannels, readables:self.inboundChannels, taskGroup:&tg, onBehalfOf:self)
			})
			self._state = .running(exitPid)
		} catch let error {
			self._state = .failed
			throw error
		}
	}
	
	fileprivate typealias ExitHandler = (State) -> Void
	fileprivate var exitStack = [ExitHandler]()
	fileprivate func whenExited(_ addHandler:@escaping(ExitHandler)) {
		switch self._state {
			case .initialized, .launching, .running, .paused:
				self.exitStack.append(addHandler)
			case .exited:
				addHandler(self.state)
			case .signaled:
				addHandler(self.state)
			default:
				break;
		}
	}
	
	public func exitCode() async throws -> Int32 {
		switch self._state {
			case .initialized:
				try await self.launch()
			case let .exited(code):
				return code
			case .signaled:
				throw Error.processSignaled
			default:
			break;
			
		}
		return try await withUnsafeThrowingContinuation { continuation in
			self.whenExited { exitResults in
				switch exitResults {
					case let .exited(code):
						continuation.resume(returning:code)
					case .signaled:
						continuation.resume(throwing:Error.processSignaled)
					default:
						continuation.resume(throwing:Error.invalidProcessState)
					break;
				}
			}
		}
	}
	
	public func write(stdin:Data) {
		guard let outChannel = outboundChannels[STDIN_FILENO]?.continuation else {
			fatalError("do not call the write() function when STDIN has not been configured in the outbound handlers")
		}
		outChannel.yield(stdin)
	}
	
	public func signal(_ signal:Int32) throws {
		guard case let .running(rpid) = self._state else {
			throw Error.invalidProcessState
		}
		switch kill(rpid, signal) {
			case 0:
				return
			default:
				throw Error.signalError
		}
	}

	public func resume() throws {
		try self.signal(SIGCONT)
	}

	public func suspend() throws {
		try self.signal(SIGSTOP)
	}

	public func terminate() throws {
		try self.signal(SIGTERM)
	}

	public func interrupt() throws {
		try self.signal(SIGINT)
	}

}