/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_posix_helpers

public actor ProcessInterface {
	/// thrown when the process interface is not in the expected state for the requested operation.
	public struct InvalidProcessStateError:Swift.Error {
		/// the state that was expected when the operation was requested.
		public let expectedState:State
		/// the actual state of the process when the operation was requested.
		public let actualState:State
	}

	/// this represents the state of a process that is being managed by the ProcessInterface actor.
	public enum State:Sendable {
		/// the process interface is initialized but not yet launched.
		case initialized
		/// the process interface is in the process of launching. a pid_t is not yet available, additionally, the launch process may fail instead of returning a pid_t.
		case launching
		/// the process is running as the current pid_t value.
		case running(pid_t)
		/// the process has been reaped with the specified result outcome.
		case reaped(ExitResult)
	}

	/// Represents the result of a process exit after it has been reaped with `waitpid()`.
	public enum ExitResult:Sendable {
		/// The process exited normally with the specified exit code.
		case exited(Int32)
		/// The process was terminated by a signal with the specified signal code.
		case signaled(Int32)
	}

	/// The current operating state of the process. This is a primary pillar of logic for the ProcessInterface functionality.
	public private(set) var state:State = .initialized

	/// The command that the process will execute when launched.
	public let command:Command

	/// Initialize a process interface with a command.
	/// - Parameter cmd: The command to execute.
	public init(_ command:consuming Command) {
		self.command = command
	}

	/// Initialize a process interface with a command and a set of data channels.
	/// - Parameters:
	/// 	- cmd: The command to execute.
	/// 	- dataChannels: A dictionary of file handle values to data channels. The keys are the file handle values, and the values are the data channels.
	public init(_ command:Command, dataChannels:[Int32:DataChannel]) {
		self.command = command
		self.dataChannels = dataChannels
	}

	private var dataChannels:[Int32:DataChannel] = [
		STDOUT_FILENO:.write(.toParentProcess(stream:.init(), separator:[0x0A])),
		STDERR_FILENO:.write(.toParentProcess(stream:.init(), separator:[0x0A])),
		STDIN_FILENO:.read(.fromParentProcess(stream:.init()))
	]
	/// access or assign a writable data stream to the process of a specified file handle value.
	public subscript(writer fh:Int32) -> DataChannel.ChildWrite? {
		set {
			switch state {
				case .initialized:
					if newValue != nil {
						dataChannels[fh] = .write(newValue!)
					} else {
						dataChannels[fh] = nil
					}
				default:
					fatalError("SwiftSlash critical error :: cannot modify the data streams of a process after it has been launched.")
			}
		}
		get {
			switch dataChannels[fh] {
				case .write(let config):
					return config
				default:
					return nil
			}
		}
	}
	/// access or assign a readable data stream to the process of a specified file handle value.
	public subscript(reader fh:Int32) -> DataChannel.ChildRead? {
		set {
			switch state {
				case .initialized:
					if newValue != nil {
						dataChannels[fh] = .read(newValue!)
					} else {
						dataChannels[fh] = nil
					}
				default:
					fatalError("SwiftSlash critical error :: cannot modify the data streams of a process after it has been launched.")
			}
		}
		get {
			switch dataChannels[fh] {
				case .read(let config):
					return config
				default:
					return nil
			}
		}
	}

	public func run() async throws -> ExitResult {
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
							state = .reaped(.exited(exitCode))
							try await tg.waitForAll()
							return .exited(exitCode)
						case .signaled(let sigCode):
							state = .reaped(.signaled(sigCode))
							try await tg.waitForAll()
							return .signaled(sigCode)
						default:
							fatalError("SwiftSlash critical error :: process exited with an unknown state.")
					}	
				}
			default:
				// the process has already been launched so we cannot proceed with the launch.
				throw InvalidProcessStateError(expectedState:.initialized, actualState:state)
		}
	}
}

extension ProcessInterface.ExitResult:Hashable, Equatable, CustomDebugStringConvertible {
	/// equatable implementation
	public static func == (lhs:ProcessInterface.ExitResult, rhs:ProcessInterface.ExitResult) -> Bool {
		switch (lhs, rhs) {
			case (.exited(let lhsExitCode), .exited(let rhsExitCode)):
				return lhsExitCode == rhsExitCode
			case (.signaled(let lhsSignal), .signaled(let rhsSignal)):
				return lhsSignal == rhsSignal
			default:
				return false
		}
	}

	/// hashable implementation
	public func hash(into hasher:inout Hasher) {
		switch self {
			case .exited(let exitCode):
				hasher.combine(0)
				hasher.combine(exitCode)
			case .signaled(let sig):
				hasher.combine(1)
				hasher.combine(sig)
		}
	}

	public var debugDescription: String {
		switch self {
			case .exited(let exitCode):
				return "ProcessInterface.ExitResult.exited(\(exitCode))"
			case .signaled(let sigCode):
				return "ProcessInterface.ExitResult.signaled(\(sigCode))"
		}
	}
}

extension ProcessInterface.State:Hashable, Equatable {
	public static func == (lhs: ProcessInterface.State, rhs: ProcessInterface.State) -> Bool {
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

/*extension ProcessInterface {
	/// convenience variable that returns access to the stdin stream of the process. this is the equivalent of referencing `instance.inbound[STDIN_FILENO]`.
	public var stdin:NAsyncStream<[UInt8], Never>? {
		set {
			inbound[STDIN_FILENO] = newValue
		}
		get {
			return inbound[STDIN_FILENO]
		}
	}
	/// convenience variable that returns access to the stdout stream of the process. this is the equivalent of referencing `instance.outbound[STDOUT_FILENO]`.
	public var stdout:NAsyncStream<[UInt8], Never>? {
		set {
			outbound[STDOUT_FILENO] = newValue
		}
		get {
			return outbound[STDOUT_FILENO]
		}
	}
	/// convenience variable that returns access to the stderr stream of the process. this is the equivalent of referencing `instance.outbound[STDERR_FILENO]`.
	public var stderr:NAsyncStream<[UInt8], Never>? {
		set {
			outbound[STDERR_FILENO] = newValue
		}
		get {
			return outbound[STDERR_FILENO]
		}
	}
}*/
