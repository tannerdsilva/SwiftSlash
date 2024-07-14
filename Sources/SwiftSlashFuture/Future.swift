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

	public borrowing func setSuccess(_ result:R) {
		let op = Unmanaged.passRetained(ContainedResult(result:result)).toOpaque()
		guard _cswiftslash_future_t_broadcast_res_val(prim, 1, op) else {
			_ = Unmanaged<ContainedResult>.fromOpaque(op).takeRetainedValue()
			return
		}
	}

	public borrowing func setFailure(_ error:Swift.Error) {
		let op = Unmanaged.passRetained(ContainedError(error:error)).toOpaque()
		guard _cswiftslash_future_t_broadcast_res_throw(prim, 1, op) else {
			_ = Unmanaged<ContainedError>.fromOpaque(op).takeRetainedValue()
			return
		}
	}

	private struct AwaitResult {
		private let cont:UnsafeMutablePointer<UnsafeContinuation<R, Swift.Error>>
		private init(_ cont:UnsafeMutablePointer<UnsafeContinuation<R, Swift.Error>>) {
			self.cont = cont
		}
		fileprivate static func expose(_ cont:consuming UnsafeContinuation<R, Swift.Error>, _ handlerF:(UnsafeMutableRawPointer) -> Void) {
			withUnsafeMutablePointer(to:&cont) {
				var newSelf = AwaitResult($0)
				withUnsafeMutablePointer(to:&newSelf) {
					handlerF($0)
				}
			}
		}
		borrowing func resume(returning result:consuming R) {
			cont.pointee.resume(returning:result)
		}
		borrowing func resume(throwing error:consuming Swift.Error) {
			cont.pointee.resume(throwing:error)
		}
	}

	public func blockForResult() -> Result<R, Swift.Error> {
		var res:Result<R, Swift.Error>? = nil
		withUnsafeMutablePointer(to:&res) { resPtr in
			_cswiftslash_future_t_wait_sync(prim, resPtr, {
				$2!.assumingMemoryBound(to:AwaitResult.self).pointee.resume(returning:Unmanaged<ContainedResult>.fromOpaque($1!).takeUnretainedValue().result)
			}, {
				$2!.assumingMemoryBound(to:AwaitResult.self).pointee.resume(throwing:Unmanaged<ContainedError>.fromOpaque($1!).takeUnretainedValue().error)
			}, {
				$0!.assumingMemoryBound(to:AwaitResult.self).pointee.resume(throwing:CancellationError())
			})
		}
		return res!
	}
	
	public func waitForResult() async throws -> R {
		return try await withUnsafeThrowingContinuation({ (cont:UnsafeContinuation<R, Swift.Error>) in
			AwaitResult.expose(cont) { awaitResult in
				_cswiftslash_future_t_wait_sync(prim, awaitResult, {
					$2!.assumingMemoryBound(to:UnsafeContinuation<R, Swift.Error>.self).pointee.resume(returning:Unmanaged<ContainedResult>.fromOpaque($1!).takeUnretainedValue().result)
				}, {
					$2!.assumingMemoryBound(to:UnsafeContinuation<R, Swift.Error>.self).pointee.resume(throwing:Unmanaged<ContainedError>.fromOpaque($1!).takeUnretainedValue().error)
				}, {
					$0!.assumingMemoryBound(to:UnsafeContinuation<R, Swift.Error>.self).pointee.resume(throwing:CancellationError())
				})
			}
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
