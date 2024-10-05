import __cswiftslash_future
import SwiftSlashContained

/// a reference type that represents a result that will be available in the future.
public final class Future<R>:@unchecked Sendable {

	// the deallocator function type for a successful result.
	public typealias SuccessfulResultDeallocator = (R) -> Void
	
	/// thrown when a result is set on a future that is already set.
	public struct InvalidStateError:Swift.Error {}

	/// the underlying c primitive that this future wraps.
	private let prim:UnsafeMutablePointer<_cswiftslash_future_t>

	/// the deallocator function that this instance will use when it is destroyed.
	private let successDeallocator:SuccessfulResultDeallocator?

	/// creates a new instance of Future.
	/// - parameters:
	/// 	- successfulResultDeallocator: a user defined deallocator function that is called when the future is destroyed and the result is successful. if nil, the result is not have any deallocation work done (assumed to be a swift native type).
	public init(successfulResultDeallocator:SuccessfulResultDeallocator? = nil) {
		self.prim = _cswiftslash_future_t_init()
		self.successDeallocator = successfulResultDeallocator
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

	/// assign a function to be called when the result of the future is known. this function may be fired immediately on the current thread or on a different thread at a later time. 
	public borrowing func whenResult(_ callback:@escaping (Result<R, Swift.Error>) -> Void) {
		_cswiftslash_future_t_wait_async(prim, nil, { resType, resPtr, ctx in
			callback(.success(Unmanaged<Contained<R>>.fromOpaque(resPtr!).takeUnretainedValue().value()))
		}, { errType, errPtr, ctx in
			callback(.failure(Unmanaged<Contained<Swift.Error>>.fromOpaque(errPtr!).takeUnretainedValue().value()))
		}, { ctx in
			fatalError("swiftslash - cancellation on c primitive not utilized - \(#file):\(#line)")
		})
	}
	
	/// asyncronously wait for the result of the future.
	/// - returns: the return value of the future.
	/// - throws: any error that was assigned to the future in place of a valid return instance.
	public borrowing func get() async throws -> R {
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
	public borrowing func result() async -> Result<R, Swift.Error> {
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
		withUnsafeMutablePointer(to:&result, { rptr in
			_cswiftslash_future_t_destroy(prim, rptr, { etyp, eptr, ctx in
				ctx!.assumingMemoryBound(to:(R?, Swift.Error?).self).pointee = (Unmanaged<Contained<R>>.fromOpaque(eptr!).takeRetainedValue().value(), nil)
			}, { etyp, eptr, ctx in
				ctx!.assumingMemoryBound(to:(R?, Swift.Error?).self).pointee = (nil, Unmanaged<Contained<Swift.Error>>.fromOpaque(eptr!).takeRetainedValue().value())
			})
		})

		// call the explicit deallocator if the result is successful and one was provided.
		if let successDeallocator = successDeallocator, let result = result.0 {
			successDeallocator(result)
		}

		result = (nil, nil)
		prim.deinitialize(count:1).deallocate()
	}
}


fileprivate let _cswiftslash_future_t_valH:future_result_val_handler_f = { resType, resPtr, ctx in
	return _cswiftslash_future_t_init(resType, resPtr, ctx)
}

