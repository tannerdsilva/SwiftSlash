import __cswiftslash
import SwiftSlashFuture

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

/// represents a pthread that is actively running. can be used to cancel a pthread before it returns or to await the result of the pthread.
internal struct LaunchedPThread {

	/// the pthread primitive that was launched.
	private let pt:_cswiftslash_pthread_t_type

	/// the future that will be set after the work is joined.
	private let rf:Future<UnsafeMutableRawPointer>

	/// the type of workspace that is being used in the pthread.
	private let runningType:any PThreadWork.Type
	
	internal init(_ pthread:consuming _cswiftslash_pthread_t_type, future:consuming Future<UnsafeMutableRawPointer>, type:any PThreadWork.Type) {
		pt = pthread
		rf = future
		runningType = type
	}

	// cancels a pthread before it returns.
	internal borrowing func cancel() throws {
		// cancel pthread
		guard pthread_cancel(pt) == 0 else {
			throw CancellationError()
		}
		// send signal
		guard pthread_kill(pt, SIGUSR1) == 0 else {
			throw CancellationError()
		}
	}
	
	internal func get() async throws -> UnsafeMutableRawPointer? {
		return try await rf.get()
	}

	internal func result() async -> Result<UnsafeMutableRawPointer, Swift.Error> {
		return await rf.result()
	}

	internal consuming func join() {
		var result:UnsafeMutableRawPointer? = nil
		guard pthread_join(pt, &result) == 0 else {
			fatalError("pthread_join failed")
		}
	}
}