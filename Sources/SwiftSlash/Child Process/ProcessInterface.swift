/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_posix_helpers

/// Comprehensive tool for launching `Command`s.
/// - NOTE: When SwiftSlash launches a process, the launched process is referred to as a *child* process.
public actor ChildProcess {
	/// Thrown when the process interface is not in the expected state for the requested operation.
	public struct InvalidProcessStateError:Swift.Error {
		/// The state that was expected when the operation was requested.
		public let expectedState:State
		/// The actual state of the process when the operation was requested.
		public let actualState:State
	}
	
	/// Thrown when a signal code failed send to the child process.
	public enum SignalError:Swift.Error {
		/// Thrown when the the host system kernel is unsuccessful at sending the signal to the child process.
		/// - Parameter errno: The system `errno` that was returned in correspondence with the failure.
		case systemSignalError(errno:Int32)
		/// Thrown when the process was found to be at an incorrect lifecycle state to send a signal. This means the process has either not launched, or has already exited.
		case invalidState(InvalidProcessStateError)
	}

	/// Represents the various states that a child process may be in while going through its lifecycle.
	public enum State:Sendable {
		/// The process interface is initialized, but not yet launched.
		case initialized
		/// The process interface is in the process of launching. a `pid_t` is not yet available, additionally, the launch process may fail instead of returning a `pid_t`.
		case launching
		/// The process is running as the current pid_t value.
		case running(pid_t)
		/// The process has been reaped with the specified result outcome.
		case reaped(Exit)
	}

	/// Represents the result of a process exit after it has been reaped with `waitpid()`.
	public enum Exit:Sendable {
		/// The process exited normally with the specified exit code.
		case code(Int32)
		/// The process was terminated by a signal with the specified signal code.
		case signal(Int32)
	}

	/// The current operating state of the process. This is a primary pillar of logic for the ChildProcess functionality.
	public private(set) var state:State = .initialized

	/// The command associated with the child process instance.
	public let command:Command

	/// The data channels that will be launched.
	private let dataChannels:[Int32:DataChannel]

	/// Initialize a process interface with a command and a set of data channels.
	/// - Parameters:
	/// 	- command: The command to execute.
	/// 	- dataChannels: Data channels to bind to the child process. The keys of this dictionary are the file handle values that will be assigned to the child process (values of `STDOUT_FILENO`, `STDIN_FILENO`, etc).
	public init(_ command:Command, dataChannels:[Int32:DataChannel] = [
		STDOUT_FILENO : .write(.toParentProcess(stream:.init(), separator:[0x0A])),
		STDERR_FILENO : .write(.toParentProcess(stream:.init(), separator:[0x0A])),
		STDIN_FILENO : .read(.fromParentProcess(stream:.init()))
	]) {
		self.command = command
		self.dataChannels = dataChannels
	}
	
	/// Access a data stream to the process of a specified file handle value.
	/// - Returns: The data channel for the specified file handle, or `nil` if none was found.
	public nonisolated subscript(channel fh:Int32) -> DataChannel? {
		get {
			return dataChannels[fh]
		}
	}
	
	/// Convenience subscript for accessing the data channel that is already known to be a writable stream.
	/// - WARNING: This subscript will throw a fatal error (crashing the parent process) if the data channel is found to be a ``SwiftSlash/DataChannel/ChildRead`` stream.
	/// - Returns: The writing interface to the child process, or `nil` if the file handle is not configured.
	public nonisolated subscript(writer fh:Int32) -> DataChannel.ChildWrite? {
		get {
			switch dataChannels[fh] {
				case .write(let config):
					return config
				case .read(_):
					fatalError("SwiftSlash critical error :: attempted to access a writable data stream but the data channel is configured as a readable stream. \(#file):\(#line)")
				case .none:
					return nil
			}
		}
	}
	/// Convenience subscript for accessing the data channel that is already known to be a readable stream.
	/// - WARNING: This subscript will throw a fatal error (crashing the parent process) if the data channel is found to be a ``SwiftSlash/DataChannel/ChildWrite`` stream.
	/// - Returns: The reading interface bound to the child process, or `nil` if the file handle is not configured.
	public nonisolated subscript(reader fh:Int32) -> DataChannel.ChildRead? {
		get {
			switch dataChannels[fh] {
				case .read(let config):
					return config
				case .write(_):
					fatalError("SwiftSlash critical error :: attempted to access a readable data stream but the data channel is configured as a writable stream. \(#file):\(#line)")
				case .none:
					return nil
			}
		}
	}
	
	/// Launches the child process by executing the configured command with the configured data channels.
	/// This function will not return until the child process exits.
	/// - Returns: The exit or signal code that the child process exited with.
	public func run() async throws -> Exit {
		// check the current state of the process. 
		switch state {
			case .initialized:
				
				// the process has not been launched yet so we may proceed with the launch.
				state = .launching
				
				return try await withThrowingTaskGroup(of:Void.self) { tg in
					// create a launch package.
					let launchPackage = ProcessLogistics.LaunchPackage(
						exe:command.executable,
						arguments:command.arguments,
						workingDirectory:command.workingDirectory,
						env:command.environment,
						dataChannels:dataChannels
					)
					
					// launch the package.
					let preapredPackage = try await ProcessLogistics.launch(package:launchPackage)
					
					// update state
					state = .running(preapredPackage.launchedPID)
					
					// launch the reader and writer loops that are associated with the running process.
					for curWrite in preapredPackage.writeTasks {
						curWrite.launch(taskGroup:&tg)
					}
					for curRead in preapredPackage.readTasks {
						curRead.launch(taskGroup:&tg)
					}
					
					// reap the running process
					switch await preapredPackage.launchedPID.waitPID() {
						case .exited(let exitCode):
							state = .reaped(.code(exitCode))
							try await tg.waitForAll()
							return .code(exitCode)
						case .signaled(let sigCode):
							state = .reaped(.signal(sigCode))
							try await tg.waitForAll()
							return .signal(sigCode)
						case .failed(let err):
							throw ReapError(errnoValue:err)
					}
				}
			default:
				// the process has already been launched so we cannot proceed with the launch.
				throw InvalidProcessStateError(expectedState:.initialized, actualState:state)
		}
	}
	
	/// Send a signal to the child process.
	/// - Parameter code: The signal code to send to the child process.
	/// - Throws: `InvalidProcessStateError` is thrown if the process is not running.
	public func signal(_ code:Int32) throws(SignalError) {
		switch state {
			case .running(let pid):
				let killReturnValue = kill(pid, code)
				guard killReturnValue == 0 else {
					throw .systemSignalError(errno:__cswiftslash_get_errno())
				}
			default:
				throw .invalidState(InvalidProcessStateError(expectedState:.running(0), actualState:state))
		}
	}
}

extension ChildProcess {
	/// Convenience variable that returns access to the stdin stream of the process.
	public nonisolated var stdin:DataChannel.ChildRead.ParentWrite {
		get {
			switch self[reader:STDIN_FILENO] {
				case .fromParentProcess(stream:let strm):
					return strm
				default:
					fatalError("SwiftSlash ChildProces fatal error :: STDIN_FILENO has a non-standard configuration, therefore, the convenience variables cannot be used. This is a user error. \(#file):\(#line)")
			}
		}
	}
	/// Convenience variable that returns access to the stdout stream of the process.
	public nonisolated var stdout:DataChannel.ChildWrite.ParentRead {
		get {
			switch self[writer:STDOUT_FILENO] {
				case .toParentProcess(stream:let strm, separator:_):
					return strm
				default:
					fatalError("SwiftSlash ChildProces fatal error :: STDOUT_FILENO has a non-standard configuration, therefore, the convenience variables cannot be used. This is a user error. \(#file):\(#line)")
			}
		}
	}
	/// Convenience variable that returns access to the stderr stream of the process.
	public nonisolated var stderr:DataChannel.ChildWrite.ParentRead {
		get {
			switch self[writer:STDERR_FILENO] {
				case .toParentProcess(stream:let strm, separator:_):
					return strm
				default:
					fatalError("SwiftSlash ChildProces fatal error :: STDERR_FILENO has a non-standard configuration, therefore, the convenience variables cannot be used. This is a user error. \(#file):\(#line)")
			}
		}
	}
}

extension ChildProcess.Exit:Hashable, Equatable, CustomDebugStringConvertible {
	public static func == (lhs:ChildProcess.Exit, rhs:ChildProcess.Exit) -> Bool {
		switch (lhs, rhs) {
			case (.code(let lhsExitCode), .code(let rhsExitCode)):
				return lhsExitCode == rhsExitCode
			case (.signal(let lhsSignal), .signal(let rhsSignal)):
				return lhsSignal == rhsSignal
			default:
				return false
		}
	}
	public func hash(into hasher:inout Hasher) {
		switch self {
			case .code(let exitCode):
				hasher.combine(0)
				hasher.combine(exitCode)
			case .signal(let sig):
				hasher.combine(1)
				hasher.combine(sig)
		}
	}
	public var debugDescription: String {
		switch self {
			case .code(let exitCode):
				return "ChildProcess.Exit.exited(\(exitCode))"
			case .signal(let sigCode):
				return "ChildProcess.Exit.signaled(\(sigCode))"
		}
	}
}

extension ChildProcess.State:Hashable, Equatable {
	public static func == (lhs: ChildProcess.State, rhs: ChildProcess.State) -> Bool {
		switch (lhs, rhs) {
			case (.initialized, .initialized):
				return true
			case (.launching, .launching):
				return true
			case (.running(let lhsPID), .running(let rhsPID)):
				return lhsPID == rhsPID
			case (.reaped(let lhsResult), .reaped(let rhsResult)):
				return lhsResult == rhsResult
			default:
				return false
		}
	}
	public func hash(into hasher: inout Hasher) {
		switch self {
			case .initialized:
				hasher.combine(0)
			case .launching:
				hasher.combine(1)
			case .running(let pid):
				hasher.combine(2)
				hasher.combine(pid)
			case .reaped(let result):
				hasher.combine(3)
				hasher.combine(result)
		}
	}
}
