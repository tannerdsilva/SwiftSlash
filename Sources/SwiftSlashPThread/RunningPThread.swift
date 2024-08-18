import __cswiftslash
import SwiftSlashFuture
import SwiftSlashContained

/// represents a pthread that is actively running. can be used to cancel a pthread before it returns or to await the result of the pthread.
public final class Running<R> {

	/// thrown when a pthread is not in the correct state for the operation the operation to be performed.
	internal struct InvalidStateError:Swift.Error {}

	private enum Mode:UInt8 {
		/// indicates that a pthread is running.
		case running = 0

		/// indicates that a pthread is canceling.
		case cancelled = 1
		
		/// indicates that a pthread is joining.
		case joining = 2

		/// indicates that a pthread is joined.
		case joined = 3
	}

	/// the pthread that is running.
	private let launched:Launched

	private let aStatus:UnsafeMutablePointer<_cswiftslash_atomic_uint8_t>

	/// initialize a new Running instance from the internal representation.
	internal init(alreadyLaunched pthread:consuming Launched) {
		launched = pthread
		aStatus = UnsafeMutablePointer<_cswiftslash_atomic_uint8_t>.allocate(capacity:1)
		launched.rf.whenResult({ [weak self] _ in
			self?.cleanup()
		})
	}

	private func cleanup() {
		switch Mode(rawValue:_cswiftslash_auint8_load(aStatus))! {
			case Mode.running:
				var expected = Mode.running.rawValue
				guard _cswiftslash_auint8_compare_exchange_weak(aStatus, &expected, Mode.joining.rawValue) else {
					return
				}
				launched.join()
				_cswiftslash_auint8_store(aStatus, Mode.joined.rawValue)
				break;
			case Mode.cancelled:
				var expected = Mode.cancelled.rawValue
				guard _cswiftslash_auint8_compare_exchange_weak(aStatus, &expected, Mode.joining.rawValue) else {
					return
				}
				launched.join()
				_cswiftslash_auint8_store(aStatus, Mode.joined.rawValue)
				break;
			case Mode.joining:
				break;
			case Mode.joined:
				break;
		}
	}

	/// cancel the running pthread.
	public func cancel() throws {
		// determine the state of the pthread.
		var expected = Mode.running.rawValue

		// attempt to take responsibility for calling cancel on the pthread.
		guard _cswiftslash_auint8_compare_exchange_weak(aStatus, &expected, Mode.cancelled.rawValue) else {
			throw InvalidStateError()
		}

		// successfully assigned the cancel state. now cancel the pthread.
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
		cleanup()
		aStatus.deallocate()
	}
}

/// represents a pthread that is actively running. can be used to cancel a pthread before it returns or to await the result of the pthread.
internal struct Launched {

	/// the pthread primitive that was launched.
	private let pt:_cswiftslash_pthread_t_type

	/// the future that will be set after the work is joined.
	internal let rf:Future<UnsafeMutableRawPointer>

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