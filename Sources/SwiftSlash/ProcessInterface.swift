import Foundation

/// ProcessInterface is the key to managing the lifecycle of any command that needs to be executed.
public actor ProcessInterface {
	public enum Error:Swift.Error {
		case invalidProcessState
		case processSignaled
		case signalError
	}
	
	internal var _state:State = .initialized
	/// The current state of this process' lifecycle
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
    /// Represents a state in the process lifecycle
	public enum State:Equatable {
        /// The process is ready for configuration
		case initialized
        /// The process is launching. A process will only linger in this state in cases of extreme concurrency (where your applications maximum file-handle count has been reached). In this case, the process will immediately launch when other file handles are closed.
		case launching
        /// The process is running. *SEE DISCLAIMER FOR USAGE DETAILS*
        ///  - **DISCLAIMER** - Do NOT call `waitpid` against this process' PID under any circumstances. Doing so will interfere with SwiftSlash and its internal process-reaping mechanism. Please use `ChildSignalCatcher` to handle values that SwiftSlash is capturing when it calls `waitpid` internally.
		case running(pid_t)
        /// The process is paused.
		case paused
        /// The child process raised a signal (enclosed) that caused it to exit.
		case signaled(Int32)
        /// The process exited cleanly with the enclosed exit code.
		case exited(Int32)
        /// The process failed to launch.
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
	
	/// Specifies all outbound data channels (mapping to file handles that the launched process will read from)
	public var outboundChannels:[Int32:DataChannel.Outbound]

	/// Specifies all inbound data channels (mapping to file handles that the launched process will write to)
	public var inboundChannels:[Int32:DataChannel.Inbound]
    
    /// Convenience variable to access the async data stream mapped to `STDOUT` handle of the running process
	public var stdout:AsyncStream<Data> {
		get {
			guard let captureChannel = inboundChannels[STDOUT_FILENO] else {
				fatalError("do not use the stdout convenience property for channels that have not been configured")
			}
			return captureChannel.stream
		}
	}
    /// Convenience variable to access the async data stream mapped to `STDERR` handle of the running process
	public var stderr:AsyncStream<Data> {
		get {
			guard let captureChannel = inboundChannels[STDERR_FILENO] else {
				fatalError("do not use the stderr convenience property for channels that have not been configured ")
			}
			return captureChannel.stream
		}
	}
    
    /// The command that will be launched as a child process
	public let command:Command
    
    /// Initialize a new ProcessInterface instance.
    /// - Parameters:
    ///   - command: The Command to launch
    ///   - stdin: `STDIN` configuration for this process. Default: `.active`
    ///   - stdout: `STDOUT` configuration for this process. Default: `.active(.lf)`
    ///   - stderr: `STDERR` configuration for this process. Default: `.active(.lf)`
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
    
    /// Launch the command
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
    
    /// Await the exit code of the process.
    ///   - The command will launch if it is not already launched
    ///   - This function will throw an error if the process raised a signal or failed to launch
    ///   - Multiple concurrent tasks can await an exit code of a single ProcessInterface instance
    /// - Returns: The exit code of the process
	public func exitCode() async throws -> Int32 {
		switch self._state {
			case .initialized:
				try await self.launch()
			case let .exited(code):
				return code
			case .signaled:
                throw Error.processSignaled
            case .failed:
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
	
    /// Convenience function to write data to the STDIN handle of the running process
	public func write(stdin:Data) {
		guard let outChannel = outboundChannels[STDIN_FILENO]?.continuation else {
			fatalError("do not call the write() function when STDIN has not been configured in the outbound handlers")
		}
		outChannel.yield(stdin)
	}
	
    /// Sends a signal to the running process
    ///   - This function will throw an `.invalidProcessState` error if the process is not running
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

    /// Convenience function to send the SIGCONT signal to the running process
	public func resume() throws {
		try self.signal(SIGCONT)
	}
    
    /// Convenience function to send the SIGSTOP signal to the running process
	public func suspend() throws {
		try self.signal(SIGSTOP)
	}
    
    /// Convenience function to send the SIGTERM signal to the running process
	public func terminate() throws {
		try self.signal(SIGTERM)
	}
    
    /// Convenience function to send the SIGINT signal to the running process
	public func interrupt() throws {
		try self.signal(SIGINT)
	}
}
