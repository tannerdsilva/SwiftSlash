import __cswiftslash

/// a reference type that represents a result that will be available in the future.
public final class Future<R>:@unchecked Sendable {
	
	/// thrown when a result is set on a future that is already set.
	public struct InvalidStateError:Swift.Error {}

	/// a private class that represents a swift error as a reference. initial referencing and dereferencing is managed entirely enternally by the future, the user never needs to know this exists.
	private final class ContainedError {
		/// the error that this instance is containing.
		internal let error:Swift.Error

		/// creates a new instance of ContainedError.
		internal init(error:Swift.Error) {
			self.error = error
		}
	}

	/// a private class that represents a successful result as a reference. initial referencing and dereferencing is managed entirely enternally by the future, the user never needs to know this exists.
	private final class ContainedResult {
		/// the result that this instance is containing.
		internal let result:R
		
		/// creates a new instance of ContainedResult.
		internal init(result:R) {
			self.result = result
		}
	}

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
	public func setSuccess(_ result:R) throws {
		let op = Unmanaged.passRetained(ContainedResult(result:result)).toOpaque()
		guard _cswiftslash_future_t_broadcast_res_val(prim, 1, op) else {
			_ = Unmanaged<ContainedResult>.fromOpaque(op).takeRetainedValue()
			throw InvalidStateError()
		}
	}

	/// assign a failure to the future.
	/// - parameters:
	/// 	- error: the error to assign to the future.
	/// - throws: InvalidStateError if the future is already set with a result or error.
	public func setFailure(_ error:Swift.Error) throws {
		let op = Unmanaged.passRetained(ContainedError(error:error)).toOpaque()
		guard _cswiftslash_future_t_broadcast_res_throw(prim, 1, op) else {
			_ = Unmanaged<ContainedError>.fromOpaque(op).takeRetainedValue()
			throw InvalidStateError()
		}
	}
	
	/// asyncronously wait for the result of the future.
	/// - returns: the return value of the future.
	/// - throws: any error that was assigned to the future in place of a valid return instance.
	public func get() async throws -> R {
		return try await withUnsafeThrowingContinuation({ (cont:UnsafeContinuation<R, Swift.Error>) in
			_cswiftslash_future_t_wait_sync(prim, nil, { resType, resPtr, ctx in
				cont.resume(returning:Unmanaged<ContainedResult>.fromOpaque(resPtr!).takeUnretainedValue().result)
			}, { errType, errPtr, ctx in
				cont.resume(throwing:Unmanaged<ContainedError>.fromOpaque(errPtr!).takeUnretainedValue().error)					
			}, { ctx in
				fatalError("swiftslash - cancellation on c primitive not utilized - \(#file):\(#line)")
			})
		})
	}

	// public func block() -> Result<R, Swift.Error> {
	// 	var res:Result<R, Swift.Error>?
	// 	withUnsafeMutablePointer(to:&res) { (resultPtr:UnsafeMutablePointer<Result<R, Swift.Error>?>) in
	// 		_cswiftslash_future_t_wait_sync(prim, resultPtr, { resType, resPtr, ctx in
	// 			ctx!.assumingMemoryBound(to:Result<R, Swift.Error>?.self).pointee = .success(Unmanaged<ContainedResult>.fromOpaque(resPtr!).takeUnretainedValue().result)
	// 		}, { errType, errPtr, ctx in
	// 			ctx!.assumingMemoryBound(to:Result<R, Swift.Error>?.self).pointee = .failure(Unmanaged<ContainedError>.fromOpaque(errPtr!).takeUnretainedValue().error)
	// 		}, { ctx in
	// 			fatalError("swiftslash - cancellation on c primitive not utilized - \(#file):\(#line)")
	// 		})
	// 	}
	// 	return res!
	// }

	/// asyncronously wait for the result of the future.
	/// - returns: the result of the future.
	public func result() async -> Result<R, Swift.Error> {
		return await withUnsafeContinuation({ (cont:UnsafeContinuation<Result<R, Swift.Error>, Never>) in
			_cswiftslash_future_t_wait_sync(prim, nil, { resType, resPtr, ctx in
				cont.resume(returning:.success(Unmanaged<ContainedResult>.fromOpaque(resPtr!).takeUnretainedValue().result))
			}, { errType, errPtr, ctx in
				cont.resume(returning:.failure(Unmanaged<ContainedError>.fromOpaque(errPtr!).takeUnretainedValue().error))
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
				ctx!.assumingMemoryBound(to:(R?, Swift.Error?).self).pointee = (Unmanaged<ContainedResult>.fromOpaque(eptr!).takeRetainedValue().result, nil)
			}, { etyp, eptr, ctx in
				ctx!.assumingMemoryBound(to:(R?, Swift.Error?).self).pointee = (nil, Unmanaged<ContainedError>.fromOpaque(eptr!).takeRetainedValue().error)
			})
		}) == 0 else {
			fatalError("failed to destroy future - \(#file):\(#line)")
		}
		result = (nil, nil)
		prim.deallocate()
	}
}
