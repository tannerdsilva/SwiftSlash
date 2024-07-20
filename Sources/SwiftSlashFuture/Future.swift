import __cswiftslash
import SwiftSlashContained

/// a reference type that represents a result that will be available in the future.
public final class Future<R>:@unchecked Sendable {
	
	/// thrown when a result is set on a future that is already set.
	public struct InvalidStateError:Swift.Error {}

	// /// a private class that represents a swift error as a reference. initial referencing and dereferencing is managed entirely enternally by the future, the user never needs to know this exists.
	// private final class ContainedError {
	// 	/// the error that this instance is containing.
	// 	internal let error:Swift.Error

	// 	/// creates a new instance of ContainedError.
	// 	internal init(error:Swift.Error) {
	// 		self.error = error
	// 	}
	// }

	/// the underlying c primitive that this future wraps.
	private let prim:UnsafeMutablePointer<_cswiftslash_future_t>

	/// creates a new instance of Future.
	/// - parameters:
	/// 	- successfulResultDeallocator: a user defined deallocator function that is called when the future is destroyed and the result is successful.
	public init() {
		self.prim = UnsafeMutablePointer<_cswiftslash_future_t>.allocate(capacity:1)
		self.prim.initialize(to:_cswiftslash_future_t_init())
	}

	/// assign a successful result to the future.
	/// - parameters:
	/// 	- result: the result to assign to the future.
	/// - throws: InvalidStateError if the future is already set with a result or error.
	public borrowing func setSuccess(_ result:R) throws {
		let op = Unmanaged.passRetained(Contained(result)).toOpaque()
		guard _cswiftslash_future_t_broadcast_res_val(prim, 1, op) else {
			_ = Unmanaged<Contained<R>>.fromOpaque(op).takeRetainedValue()
			throw InvalidStateError()
		}
	}

	/// assign a failure to the future.
	/// - parameters:
	/// 	- error: the error to assign to the future.
	/// - throws: InvalidStateError if the future is already set with a result or error.
	public borrowing func setFailure(_ error:Swift.Error) throws {
		let op = Unmanaged.passRetained(Contained(error)).toOpaque()
		guard _cswiftslash_future_t_broadcast_res_throw(prim, 1, op) else {
			_ = Unmanaged<Contained<Swift.Error>>.fromOpaque(op).takeRetainedValue()
			throw InvalidStateError()
		}
	}
	
	/// asyncronously wait for the result of the future.
	/// - returns: the return value of the future.
	/// - throws: any error that was assigned to the future in place of a valid return instance.
	public func get() async throws -> R {
		return try await withUnsafeThrowingContinuation({ (cont:UnsafeContinuation<R, Swift.Error>) in
			_cswiftslash_future_t_wait_sync(prim, nil, { resType, resPtr, ctx in
				cont.resume(returning:Unmanaged<Contained<R>>.fromOpaque(resPtr!).takeUnretainedValue().value())
			}, { errType, errPtr, ctx in
				cont.resume(throwing:Unmanaged<Contained<Swift.Error>>.fromOpaque(errPtr!).takeUnretainedValue().value())					
			}, { ctx in
				fatalError("swiftslash - cancellation on c primitive not utilized - \(#file):\(#line)")
			})
		})
	}

	/// asyncronously wait for the result of the future.
	/// - returns: the result of the future.
	public func result() async -> Result<R, Swift.Error> {
		return await withUnsafeContinuation({ (cont:UnsafeContinuation<Result<R, Swift.Error>, Never>) in
			_cswiftslash_future_t_wait_sync(prim, nil, { resType, resPtr, ctx in
				cont.resume(returning:.success(Unmanaged<Contained<R>>.fromOpaque(resPtr!).takeUnretainedValue().value()))
			}, { errType, errPtr, ctx in
				cont.resume(returning:.failure(Unmanaged<Contained<Swift.Error>>.fromOpaque(errPtr!).takeUnretainedValue().value()))
			}, { ctx in
				fatalError("swiftslash - cancellation on c primitive not utilized - \(#file):\(#line)")
			})
		})
	}

	deinit {
		// destroy the c primitive. capture the result 
		var result:(R?, Swift.Error?) = (nil, nil)
		guard withUnsafeMutablePointer(to:&result, { rptr in
			return _cswiftslash_future_t_destroy(prim.pointee, rptr, { etyp, eptr, ctx in
				ctx!.assumingMemoryBound(to:(R?, Swift.Error?).self).pointee = (Unmanaged<Contained<R>>.fromOpaque(eptr!).takeRetainedValue().value(), nil)
			}, { etyp, eptr, ctx in
				ctx!.assumingMemoryBound(to:(R?, Swift.Error?).self).pointee = (nil, Unmanaged<Contained<Swift.Error>>.fromOpaque(eptr!).takeRetainedValue().value())
			})
		}) == 0 else {
			fatalError("failed to destroy future - \(#file):\(#line)")
		}
		result = (nil, nil)
		prim.deinitialize(count:1).deallocate()
	}
}
