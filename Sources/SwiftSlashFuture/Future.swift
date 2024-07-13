import __cswiftslash

internal final class Future<R>:Sendable {
	internal typealias SuccessfulResultDeallocator = @Sendable (R) -> Void
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

	internal init(successfulResultDeallocator:SuccessfulResultDeallocator? = nil) {
		self.prim = UnsafeMutablePointer<_cswiftslash_future_t>.allocate(capacity:1)
		self.successfulResultDeallocator = successfulResultDeallocator
		self.prim.initialize(to:_cswiftslash_future_t_init())
	}

	internal func setSuccess(_ result:R) {
		let op = Unmanaged.passRetained(ContainedResult(result:result)).toOpaque()
		guard _cswiftslash_future_t_broadcast_res_val(prim, 0, op) else {
			_ = Unmanaged<ContainedResult>.fromOpaque(op).takeRetainedValue()
			return
		}
	}

	internal func setFailure(_ error:Swift.Error) {
		let op = Unmanaged.passRetained(ContainedError(error:error)).toOpaque()
		guard _cswiftslash_future_t_broadcast_res_throw(prim, 1, op) else {
			_ = Unmanaged<ContainedError>.fromOpaque(op).takeRetainedValue()
			return
		}
	}

	internal func blockForResult() -> Result<R, Swift.Error> {
		var res:Result<R, Swift.Error>? = nil
		withUnsafeMutablePointer(to:&res) { resPtr in
			_cswiftslash_future_t_wait_sync(prim, {
				resPtr.pointee = .success(Unmanaged<ContainedResult>.fromOpaque($0!).takeUnretainedValue().result)
			}, {
				resPtr.pointee = .failure(Unmanaged<ContainedError>.fromOpaque($0!).takeUnretainedValue().error)
			}, {
				resPtr.pointee = .failure(CancellationError())
			})
		}
		return res!
	}

	internal func awaitResult() async -> Result<R, Swift.Error> {
		await withCheckedContinuation { cont in
			cont.resume(returning:blockForResult())
		}
	}

	deinit {
		_cswiftslash_future_t_destroy(prim.pointee, {
			let val = Unmanaged<ContainedResult>.fromOpaque($0!).takeRetainedValue().result
			self.successfulResultDeallocator?(val)
		}, {
			_ = Unmanaged<ContainedError>.fromOpaque($0!).takeRetainedValue()
		})
		prim.deinitialize(count:1).deallocate()
	}
}