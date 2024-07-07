import __cswiftslash

public final class Future {
	private final class ContainedError {
		internal let error:Error
		internal init(error:Error) {
			self.error = error
		}
	}
	private var prim:_cswiftslash_future_t = _cswiftslash_future_t_init()

	internal func setSuccess() {
		_cswiftslash_future_t_broadcast_res_val(&prim, 0, nil)
	}

	internal func setFailure(_ error:Error) {
		let err = ContainedError(error:error)
		_cswiftslash_future_t_broadcast_res_throw(&prim, 1, Unmanaged.passRetained(err).toOpaque())
	}

	internal func waitForResult() async throws -> Result<Void, Swift.Error> {
		let res = await withUnsafeContinuation { (cont:UnsafeContinuation<Result<Void, Swift.Error>, Never>) in
			_cswiftslash_future_t_wait_sync(&prim, { _ in
				cont.resume(returning: .success(()))
			}, { errPtr in
				cont.resume(returning: .failure(Unmanaged<ContainedError>.fromOpaque(errPtr!).takeRetainedValue().error))
			}, {
				cont.resume(returning: .failure(CancellationError()))
			})
		}
		return res
	}

	deinit {
		var primCopy = prim
		_cswiftslash_future_t_destroy(&primCopy, { _ in }, { errPtr in
			_ = Unmanaged<ContainedError>.fromOpaque(errPtr!).takeRetainedValue()
		})
	}
}