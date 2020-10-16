import Foundation
//these are the types of line breaks that can be parsed from incoming data channels
public enum LinebreakType:UInt8 {
	case cr
	case lf
	case crlf
	case immediate
}

public class ProcessInterface {
	public typealias DataHandler = (Data) -> Void
	public typealias ExitHandler = (Int32) -> Void
	
	private let internalSync = DispatchQueue(label:"com.swiftslash.instance.data-channel-monitor.reading", target:process_master_queue)
		
	/*
		State related
	*/
	public enum State:UInt8 {
		case initialized
		case running
		case suspended
		case exited
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
	private var _stdoutParseMode:LinebreakType = .cr
	public var stdoutParseMode:LinebreakType {
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
	private var _stderrParseMode:LinebreakType = .cr
	public var stderrParseMode:LinebreakType {
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
			return _exitHandler
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
		set {
			internalSync.sync { [newValue] in
				_command = newValue
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
	public func waitForExitCode() -> Int32 {
		flightGroup.wait()
		return internalSync.sync {
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
	
	public func run() throws {
    	try self.internalSync.sync {
    		guard self._state == .initialized else {
    			return
    		}
    		do {
    			self.flightGroup.enter()
    			let launchedProcess = try tt_spawn(path:self._command.executable, args:self._command.arguments, wd:self._workingDirectory, env:self._command.environment, stdout:self._stdoutHandler, stdoutParseMode:_stdoutParseMode, stderrParseMode:_stderrParseMode, stderr:self._stderrHandler, exitHandler: { [weak self] exitCode in
    				guard let self = self else {
    					return
    				}
    				self.internalSync.sync { 
    					self._exitCode = exitCode
    					self._state = .exited
    					if (self._exitHandler != nil) {
    						self._exitHandler!(exitCode)
    					}
    				}
    				self.flightGroup.leave()
    			})
    			self._state = .running
    			self._process_signature = launchedProcess
    		} catch let error {
    			self.flightGroup.leave()
    			self._state = .failed
    			throw error
    		}
		}
	}
	
//	public func writeInput
}

internal func current_process_working_directory() -> URL {
	let rawPointer = getcwd(nil, 0)
	let currentWorkingDirectoryBuffer = UnsafeMutableRawPointer(rawPointer!)
	defer {
		free(currentWorkingDirectoryBuffer)
	}
	let length = strlen(rawPointer!)
	let currentWDData = Data(bytes:currentWorkingDirectoryBuffer, count:length)
	let currentPath = String(data:currentWDData, encoding:.utf8)!
	return URL(fileURLWithPath:currentPath)
}