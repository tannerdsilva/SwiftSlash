import __cswiftslash

public final class Future<R>:Sendable {
	public typealias SuccessfulResultDeallocator = @Sendable (R) -> Void
	private final class ContainedError {
		internal let error:Swift.Error
		internal init(error:Swift.Error) {
			self.error = error
		}
	}
	private final class ContainedResult {
		internal let result:R
		internal init(result:R) {
			self.result = result
		}
	}

	private let prim:UnsafeMutablePointer<_cswiftslash_future_t>
	private let successfulResultDeallocator:SuccessfulResultDeallocator?

	public init(successfulResultDeallocator:SuccessfulResultDeallocator? = nil) {
		self.prim = UnsafeMutablePointer<_cswiftslash_future_t>.allocate(capacity:1)
		self.successfulResultDeallocator = successfulResultDeallocator
		self.prim.initialize(to:_cswiftslash_future_t_init())
	}

	public borrowing func setSuccess(_ result:consuming R) {
		let op = Unmanaged.passRetained(ContainedResult(result:result)).toOpaque()
		guard _cswiftslash_future_t_broadcast_res_val(prim, 1, op) else {
			_ = Unmanaged<ContainedResult>.fromOpaque(op).takeRetainedValue()
			return
		}
	}

	public borrowing func setFailure(_ error:consuming Swift.Error) {
		let op = Unmanaged.passRetained(ContainedError(error:error)).toOpaque()
		guard _cswiftslash_future_t_broadcast_res_throw(prim, 1, op) else {
			_ = Unmanaged<ContainedError>.fromOpaque(op).takeRetainedValue()
			return
		}
	}
	
	public func blockForResult() -> Result<R, Swift.Error> {
		var res:Result<R, Swift.Error>? = nil
		withUnsafeMutablePointer(to:&res) { resPtr in
			_cswiftslash_future_t_wait_sync(prim, resPtr, {
				$2!.assumingMemoryBound(to:Result<R, Swift.Error>?.self).pointee = .success(Unmanaged<ContainedResult>.fromOpaque($1!).takeUnretainedValue().result)
			}, {
				$2!.assumingMemoryBound(to:Result<R, Swift.Error>?.self).pointee = .failure(Unmanaged<ContainedError>.fromOpaque($1!).takeUnretainedValue().error)
			}, {
				$0!.assumingMemoryBound(to:Result<R, Swift.Error>?.self).pointee = .failure(CancellationError())
			})
		}
		return res!
	}
	
	public func waitForResult() async throws -> R {
		return try await withUnsafeThrowingContinuation({ (cont:UnsafeContinuation<R, Swift.Error>) in
			_cswiftslash_future_t_wait_async(prim, { resType, resPtr, ctx in
				cont.resume(returning:Unmanaged<ContainedResult>.fromOpaque(resPtr!).takeUnretainedValue().result)
			}, { errType, errPtr, ctx in
				cont.resume(throwing:Unmanaged<ContainedError>.fromOpaque(errPtr!).takeUnretainedValue().error)					
			}, { ctx in
				cont.resume(throwing:CancellationError())
			})
		})
	}

	deinit {
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
		if result.0 != nil {
			successfulResultDeallocator?(result.0!)
		}
		result = (nil, nil)
	}
}
