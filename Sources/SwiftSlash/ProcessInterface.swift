import SwiftSlashNAsyncStream
import __cswiftslash_posix_helpers

public actor ProcessInterface {
	
	/// this represents the state of a process that is being managed by the ProcessInterface actor.
	public enum State {
		/// the process interface is initialized but not yet launched.
		case initialized
		/// the process interface is in the process of launching. a pid_t is not yet available, additionally, the launch process may fail instead of returning a pid_t.
		case launching
		/// the process is running as the current pid_t value.
		case running(pid_t)
		/// the process is suspended.
		case suspended(pid_t)
		case signaled(Int32)
		case exited(Int32)
		case failed(Int32)
	}
	/// the current operating state of the process. this is a primary pillar of logic for the ProcessInterface functionality.
	public private(set) var state:State = .initialized

	private let command:Command

	public init(
		_ command:consuming Command
	) {
		self.command = command
	}

	/// stores all of the data channels that the process will write to.
	private var outbound:[Int32:DataChannel.ChildWriteParentRead.Configuration] = [
		STDOUT_FILENO:.createActiveConfiguration(),
		STDERR_FILENO:.createActiveConfiguration()
	]
	/// stores all of the data channels that the process will read from.
	private var inbound:[Int32:DataChannel.ChildReadParentWrite.Configuration] = [
		STDIN_FILENO:.active(stream:.init())
	]
	/// access or assign a writable data stream to the process of a specified file handle value.
	public subscript(writer fh:Int32) -> DataChannel.ChildWriteParentRead.Configuration? {
		set {
			switch state {
				case .initialized:
					guard inbound[fh] == nil else {
						fatalError("SwiftSlash critical error :: cannot assign a writing data stream when a reader has already been configured for the same handle value.")
					}
					outbound[fh] = newValue
				default:
					fatalError("SwiftSlash critical error :: cannot modify the data streams of a process after it has been launched.")
			}
			outbound[fh] = newValue
		}
		get {
			return outbound[fh]
		}
	}
	/// access or assign a readable data stream to the process of a specified file handle value.
	public subscript(reader fh:Int32) -> DataChannel.ChildReadParentWrite.Configuration? {
		set {
			switch state {
				case .initialized:
					guard outbound[fh] == nil else {
						fatalError("SwiftSlash critical error :: cannot assign a reading data stream when a writer has already been configured for the same handle value.")
					}
					inbound[fh] = newValue
				default:
					fatalError("SwiftSlash critical error :: cannot modify the data streams of a process after it has been launched.")
			}
		}
		get {
			return inbound[fh]
		}
	}
	/// returns all of the currently configured data channels for the process. this includes both the inbound and outbound channels of the process.
	public borrowing func allDataChannels() -> [Int32:DataChannel] {
		var buildChannels = [Int32:DataChannel]()
		for (fh, curOut) in outbound {
			buildChannels[fh] = .childWriting(curOut)
		}
		for (fh, curIn) in inbound {
			buildChannels[fh] = .childReading(curIn)
		}
		return buildChannels
	}

	public func runChildProcess() async throws {
		// check the current state of the process.
		switch state {
			case .initialized:
				state = .launching
				try await withThrowingTaskGroup(of:Void.self) { tg in
					let preapredPackage = try await ProcessLogistics.launch(package:ProcessLogistics.LaunchPackage(exe:command.executable, arguments:command.arguments, workingDirectory:command.workingDirectory, env:command.environment, writables:inbound, readables:outbound))
					state = .running(preapredPackage.launchedPID)
					// for curWrite in preapredPackage.writeTasks {
					// 	curWrite.launch(taskGroup:&tg)
					// }
					for curRead in preapredPackage.readTasks {
						curRead.launch(taskGroup:&tg)
					}
					// try? await tg.waitForAll()
					switch await preapredPackage.launchedPID.waitPID() {
						case .exited(let exitCode):
							// fatalError("SwiftSlash critical error :: process exited with an unknown state. \(#file):\(#line) \(exitCode)")
							guard exitCode == 0 else {
								fatalError("SwiftSlash critical error :: process exited with an unknown state. \(#file):\(#line) \(exitCode)")
							}
							state = .exited(exitCode)
						case .signaled(let sigCode):
							state = .signaled(sigCode)
						default:
							fatalError("SwiftSlash critical error :: process exited with an unknown state.")
					}
				}
				break;
			case .launching:
				throw Error.processAlreadyLaunched
			case .running(_):
				throw Error.processAlreadyLaunched
			case .suspended(_):
				throw Error.processAlreadyLaunched
			case .signaled(_):
				throw Error.processAlreadyLaunched
			case .exited(_):
				throw Error.processAlreadyLaunched
			case .failed(_):
				throw Error.processAlreadyLaunched
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
			case (.suspended(let lhsPID), .suspended(let rhsPID)):
				return lhsPID == rhsPID
			case (.signaled(let lhsSignal), .signaled(let rhsSignal)):
				return lhsSignal == rhsSignal
			case (.exited(let lhsExitCode), .exited(let rhsExitCode)):
				return lhsExitCode == rhsExitCode
			case (.failed(let lhsError), .failed(let rhsError)):
				return lhsError == rhsError
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
			case .suspended(let pid):
				hasher.combine(3)
				hasher.combine(pid)
			case .signaled(let sig):
				hasher.combine(4)
				hasher.combine(sig)
			case .exited(let exitCode):
				hasher.combine(5)
				hasher.combine(exitCode)
			case .failed(let err):
				hasher.combine(6)
				hasher.combine(err)
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
