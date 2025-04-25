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
	private var curState:State = .initialized

	/// stores all of the data channels that the process will write to.
	private var outbound:[Int32:NAsyncStream<[UInt8], Never>] = [
		STDOUT_FILENO:.init(),
		STDERR_FILENO:.init()
	]
	/// stores all of the data channels that the process will read from.
	private var inbound:[Int32:NAsyncStream<[UInt8], Never>] = [
		STDIN_FILENO:.init()
	]
	/// access or assign a writable data stream to the process of a specified file handle value.
	public subscript(writer fh:Int32) -> NAsyncStream<[UInt8], Never>? {
		set {
			switch curState {
				case .initialized:
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
	public subscript(reader fh:Int32) -> NAsyncStream<[UInt8], Never>? {
		set {
			switch curState {
				case .initialized:
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
	public borrowing func allDataChannels() -> ([Int32:NAsyncStream<[UInt8], Never>], [Int32:NAsyncStream<[UInt8], Never>]) {
		return (inbound, outbound)
	}

	public borrowing func launch() async throws {
		// check the current state of the process.
		switch curState {
			case .initialized:
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
		curState = .launching
	}
}

extension ProcessInterface {
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
}
