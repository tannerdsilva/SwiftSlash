import __cswiftslash
import SwiftSlashFuture
import SwiftSlashContained

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

public final class Running<R> {

	/// the pthread that is running.
	private var launched:Launched

	/// initialize a new Running instance from the internal representation.
	internal init(alreadyLaunched pthread:consuming Launched) {
		launched = pthread
	}

	/// cancel the running pthread.
	public func cancel() throws {
		try launched.cancel()
	}

	public func result() async throws -> Result<R, Swift.Error> {
		let result = await launched.result()
		switch result {
		case .success(let ptr):
			return .success(Unmanaged<Contained<R>>.fromOpaque(ptr).takeUnretainedValue().value())
		case .failure(let error):
			return .failure(error)
		}
	}

	deinit {
		launched.join()
	}
}

/// represents a pthread that is actively running. can be used to cancel a pthread before it returns or to await the result of the pthread.
internal struct Launched {

	/// the pthread primitive that was launched.
	private let pt:_cswiftslash_pthread_t_type

	/// the future that will be set after the work is joined.
	private let rf:Future<UnsafeMutableRawPointer>

	
	internal init(_ pthread:consuming _cswiftslash_pthread_t_type, future:consuming Future<UnsafeMutableRawPointer>) {
		pt = pthread
		rf = future
	}

	/// cancels a pthread before it returns.
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
	
	/// gets the result of the pthread.
	internal func get() async throws -> UnsafeMutableRawPointer? {
		return try await rf.get()
	}

	/// awaits the result of the pthread.
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