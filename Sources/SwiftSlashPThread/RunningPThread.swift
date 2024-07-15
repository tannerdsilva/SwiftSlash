import __cswiftslash
import SwiftSlashFuture

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

internal typealias ReturnFuture = Future<UnsafeMutableRawPointer>

/// represents a pthread that is actively running. can be used to cancel a pthread before it returns or to await the result of the pthread.
internal struct RunningPThread {

	/// the pthread primitive that was launched.
	private let pt:_cswiftslash_pthread_t_type
	/// the future that will be set after the work is joined.
	private let rf:ReturnFuture
	
	internal init(_ pthread:consuming _cswiftslash_pthread_t_type, future:consuming Future<UnsafeMutableRawPointer>) {
		pt = pthread
		rf = future
	}

	internal borrowing func cancel() throws {
		guard pthread_cancel(pt) == 0 else {
			throw CancellationError()
		}
		// send signal
		guard pthread_kill(pt, SIGUSR1) == 0 else {
			throw CancellationError()
		}
	}
	
	internal borrowing func awaitResult() async throws -> UnsafeMutableRawPointer? {
		return try await rf.waitForResult()
	}
}