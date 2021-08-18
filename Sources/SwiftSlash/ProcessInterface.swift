import Foundation
//these are the types of line breaks that can be parsed from incoming data channels
public enum DataParseMode:UInt8 {
	case cr			//parses line breaks with the cr byte
	case lf			//parses line breaks with the lf byte
	case crlf		//parses line breaks with the sequence of cr + lf
	case immediate	//does not parse line breaks, fires the data handler as soon as the data is available
}

public class ProcessInterface {
	public enum Error:Swift.Error {
		case invalidProcessState
		case processSignaled
	}
	public typealias DataHandler = (Data, ProcessInterface) -> Void
	public typealias ExitHandler = (Int32, ProcessInterface) -> Void
	
	private let internalSync = DispatchQueue(label:"com.swiftslash.instance.data-channel-monitor.reading", target:process_master_queue)
		
	/*
		State related
	*/
	public enum State:UInt8 {
		case initialized
		case running
		case suspended
		case exited
		case signaled
		case failed
	}
	private var _state:State = State.initialized
	public var state:State {
		get {
			return internalSync.sync {
				return _state
			}
		}
	}
	
	/*
		inbound I/O data handlers
	*/
	//stdout
	private var _stdoutParseMode:DataParseMode = .lf
	public var stdoutParseMode:DataParseMode {
		get {
			return internalSync.sync {
				return _stdoutParseMode
			}
		}
		set {
			internalSync.sync { [newValue] in
				_stdoutParseMode = newValue
			}
		}
	}
	private var _stdoutHandler:DataHandler? = nil
	public var stdoutHandler:DataHandler? {
		get {
			return internalSync.sync {
				return _stdoutHandler
			}
		}
		set {
			internalSync.sync { [newValue] in
				_stdoutHandler = newValue
			}
		}
	}
	//stderr
	private var _stderrParseMode:DataParseMode = .lf
	public var stderrParseMode:DataParseMode {
		get {
			return internalSync.sync {
				return _stderrParseMode
			}
		}
		set {
			internalSync.sync { [newValue] in
				_stderrParseMode = newValue
			}
		}
	}
	private var _stderrHandler:DataHandler? = nil
	public var stderrHandler:DataHandler? {
		get {
			return internalSync.sync {
				return _stderrHandler
			}
		}
		set {
			internalSync.sync { [newValue] in
				_stderrHandler = newValue
			}
		}
	}
	
	/*
		exit handler
	*/
	private var _exitHandler:ExitHandler? = nil
	public var exitHandler:ExitHandler? {
		get {
			return internalSync.sync {
				return _exitHandler
			}
		}
		set {
			internalSync.sync { [newValue] in
				_exitHandler = newValue
			}
		}
	}
	
	/*
		command, arguments
	*/
	private var _command:Command
	public var command:Command {
		get {
			return internalSync.sync {
				return _command
			}
		}
	}
	
	private var _workingDirectory:URL = CurrentProcessState.getCurrentWorkingDirectory()
	public var workingDirectory:URL {
		get {
			return internalSync.sync {
				return _workingDirectory
			}
		}
		set {
			internalSync.sync { [newValue] in
				_workingDirectory = newValue
			}
		}
	}	
	
	/*
		pid and exit code information
	*/
	private let flightGroup = DispatchGroup()
	private var _exitCode:Int32? = nil
	public var exitCode:Int32? {
		get {
			return internalSync.sync {
				return _exitCode
			}
		}
	}
	public func waitForExit() {
		flightGroup.wait()
	}
	public func waitForExitCode() throws -> Int32 {
		flightGroup.wait()
		return try internalSync.sync {
			guard _state != .signaled else {
				throw Error.processSignaled
			}
			return self._exitCode!
		}
	}
	public var pid:pid_t? {
		get {
			return internalSync.sync {
				return _process_signature?.worker
			}
		}
	}
	
	/*
		command and flight related variables
	*/
	internal var _process_signature:tt_proc_signature? = nil
	
	public init(command:Command) {
		_command = command
	}
	
	@discardableResult public func run() throws -> pid_t {
		return try self.internalSync.sync {
			guard self._state == .initialized else {
				throw Error.invalidProcessState 
			}
			do {
				self.flightGroup.enter()
				
				let outGateway:InboundDataHandler?
				if (self._stdoutHandler == nil) {
					outGateway = nil
				} else {
					outGateway = { [weak self, dh = self._stdoutHandler!] someData in
						guard self != nil else {
							return
						}
						dh(someData, self!)
					}
				}
				
				let errGateway:InboundDataHandler?
				if (self._stderrHandler == nil) {
					errGateway = nil
				} else {
					errGateway = { [weak self, dh = self._stderrHandler!] someData in
						guard self != nil else {
							return
						}
						dh(someData, self!)
					}
				}

				let launchedProcess = try tt_spawn(path:self._command.executable, args:self._command.arguments, wd:self._workingDirectory, env:self._command.environment, stdout:outGateway, stdoutParseMode:_stdoutParseMode, stderrParseMode:_stderrParseMode, stderr:errGateway, exitHandler: { [weak self] exitCode in
					guard self != nil else {
						return
					}
					let ehToFire:ExitHandler? = self.internalSync.sync {
						if (exitCode != nil) {
							self._exitCode = exitCode
							self._state = .exited
							if (self._exitHandler != nil) {
								return self._exitHandler 
							}
							return nil
						} else {
							self._state = .signaled
							return nil
						}
					}
					if (ehToFire != nil && exitCode != nil) {
						ehToFire!(exitCode!, self)
					}
					self.flightGroup.leave()
				})
				self._state = .running
				self._process_signature = launchedProcess
				return launchedProcess.worker
			} catch let error {
				self.flightGroup.leave()
				self._state = .failed
				throw error
			}
		}
	}
	
	public func write(stdin:Data) throws {
		try self.internalSync.sync {
			guard self._state == .running else {
				throw Error.invalidProcessState
			}
			self._process_signature!.stdinChannel.broadcast(stdin)
		}
	}
}