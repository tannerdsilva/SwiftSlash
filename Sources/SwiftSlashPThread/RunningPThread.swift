import __cswiftslash
import SwiftSlashFuture
import SwiftSlashContained

/// represents a pthread that is actively running. can be used to cancel a pthread before it returns or to await the result of the pthread.
public final class Running<R> {

	internal class Mode {
		internal enum Value:UInt8 {
			/// indicates that a pthread is running.
			case running = 0

			/// indicates that a pthread is cancelled. this does not mean that the pthread has exited.
			case cancelled = 1

			// indicates that the pthread is no longer running.
			case exited = 2
			
			/// indicates that a pthread is joining.
			case joining = 3

			/// indicates that a pthread is joined.
			case joined = 4
		}

		/// the internal representation of the mode.
		private var mode = _cswiftslash_atomic_uint8_t()
		internal init(initialValue ival:Value = .running) {
			_cswiftslash_auint8_store(&mode, ival.rawValue)
		}

		internal func store(value:Value) {
			_cswiftslash_auint8_store(&mode, value.rawValue)
		}

		internal func load() -> Value {
			return Value(rawValue:_cswiftslash_auint8_load(&mode))!
		}

		internal func compareExchange(expected:Value, desired:Value) -> Bool {
			var expectedUInt8 = expected.rawValue
			return _cswiftslash_auint8_compare_exchange_weak(&mode, &expectedUInt8, desired.rawValue)
		}
	}

	/// thrown when a pthread is not in the correct state for the operation the operation to be performed.
	internal struct InvalidStateError:Swift.Error {}

	/// the pthread that is running.
	private let launched:Launched

	private var status = Mode()

	/// initialize a new Running instance from the internal representation.
	internal init(alreadyLaunched pthread:consuming Launched) {
		launched = pthread
		launched.rf.whenResult({ [weak self] _ in
			self?.setExitedFromRunning()
		})
	}

	private func setExitedFromRunning() {
		switch status.load() {
		case .running:
			guard status.compareExchange(expected: .running, desired: .exited) else {
				return
			}
		case .cancelled:
			guard status.compareExchange(expected: .cancelled, desired: .exited) else {
				return
			}
		case .exited:
			fatalError("unexpected state")
		case .joining:
			return
		case .joined:
			return
		}
	}

	/// cancel the running pthread.
	public func cancel() throws {
		switch status.load() {
		case .running:
			guard status.compareExchange(expected: .running, desired: .cancelled) else {
				throw InvalidStateError()
			}
		case .cancelled:
			throw InvalidStateError()
		case .exited:
			throw InvalidStateError()
		case .joining:
			throw InvalidStateError()
		case .joined:
			throw InvalidStateError()
		}

		// successfully assigned the cancel state. now cancel the pthread.
		try launched.cancel()
	}

	public func result() async -> Result<R, Swift.Error> {
		let result = await launched.result()
		switch result {
		case .success(let ptr):
			return .success(Unmanaged<Contained<R>>.fromOpaque(ptr).takeUnretainedValue().value())
		case .failure(let error):
			return .failure(error)
		}
	}

	deinit {
		// determine if the thread needs to be cancelled before it is joined.
		switch status.load() {
		case .running:
			try! cancel()
			fallthrough
		default:
			status.store(value: .joining)
			launched.join()
			status.store(value: .joined)
		}
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
		// send signal
		guard pthread_kill(pt, SIGUSR1) == 0 else {
			throw CancellationError()
		}

		// cancel pthread
		guard pthread_cancel(pt) == 0 else {
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