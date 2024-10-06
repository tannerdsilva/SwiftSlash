import Testing

import __cswiftslash_future

import Foundation

// MARK: - Future Harness Class

fileprivate final class FutureHarness:@unchecked Sendable {

	fileprivate enum Result {
		case success(UInt8, UnsafeMutableRawPointer?)
		case failure(UInt8, UnsafeMutableRawPointer?)
	}

    // Pointer to the C future structure
    fileprivate let futurePtr:UnsafeMutablePointer<_cswiftslash_future_t>

    /// Initializes a new future instance.
    fileprivate init() {
        self.futurePtr = _cswiftslash_future_t_init()
    }

    // /// Waits asynchronously for the future to complete.ctxPtr
    // fileprivate func waitAsync() async -> Result {
	// 	var resultPtr:Result? = nil
	// 	withUnsafeMutablePointer(to:&resultPtr) { resultPtrPtr in
	// 		_cswiftslash_future_t_wait_async(futurePtr, resultPtrPtr, futureSyncResultHandler, futureErrorHandler, futureCancelHandler)
	// 	}
	// 	return resultPtr
    // }

    /// Broadcasts a result value to the future.
    @discardableResult
    fileprivate func broadcastResultValue(resType: UInt8, resVal: UnsafeMutableRawPointer?) -> Bool {
        return _cswiftslash_future_t_broadcast_res_val(self.futurePtr, resType, resVal)
    }

    /// Broadcasts an error value to the future.
    @discardableResult
    fileprivate func broadcastErrorValue(errType: UInt8, errVal: UnsafeMutableRawPointer?) -> Bool {
        return _cswiftslash_future_t_broadcast_res_throw(self.futurePtr, errType, errVal)
    }

	fileprivate final class AsyncResult {
		
		private var resultHandler:future_result_val_handler_f?
		private var errorHandler:future_result_err_handler_f?
		private var cancelHandler:future_result_cancel_handler_f?

		fileprivate init(resultHandler rh:@escaping(future_result_val_handler_f), errorHandler eh:@escaping(future_result_err_handler_f), cancelHandler ch:@escaping(future_result_cancel_handler_f)) {
			resultHandler = rh
			errorHandler = eh
			cancelHandler = ch
		}

		fileprivate func setResult(type:UInt8, result:_cswiftslash_optr_t?, contextPtr:UnsafeMutableRawPointer?) {
			resultHandler?(type, result, contextPtr)
			resultHandler = nil
			errorHandler = nil
			cancelHandler = nil
		}

		fileprivate func setError(type:UInt8, error:_cswiftslash_optr_t?, contextPtr:UnsafeMutableRawPointer?) {
			errorHandler?(type, error, contextPtr)
			resultHandler = nil
			errorHandler = nil
			cancelHandler = nil
		}

		fileprivate func setNil(contextPtr:UnsafeMutableRawPointer?) {
			cancelHandler?(contextPtr)
			resultHandler = nil
			errorHandler = nil
			cancelHandler = nil
		}
	}

	private let futureAsyncResultHandler:future_result_val_handler_f = { resType, resPtr, ctxPtr in
		ctxPtr?.assumingMemoryBound(to:AsyncResult.self).pointee.setResult(type:resType, result:resPtr, contextPtr:ctxPtr)
	}
	private let futureAsyncErrorHandler:future_result_err_handler_f = { errType, errPtr, ctxPtr in
		ctxPtr?.assumingMemoryBound(to:AsyncResult.self).pointee.setError(type:errType, error:errPtr, contextPtr:ctxPtr)
	}
	private let futureAsyncCancelHandler:future_result_cancel_handler_f = { ctxPtr in
		ctxPtr?.assumingMemoryBound(to:AsyncResult.self).pointee.setNil(contextPtr:ctxPtr)
	}

	/// Waits synchronously for the future to complete.

	private struct SyncResult {
		fileprivate struct NoResultAvailable:Swift.Error {}
		private enum ResultOrNoResult {
			case noResult
			case result(Result?)
		}
		private var ron:ResultOrNoResult = .noResult
		private var assPT:pthread_t? = nil
		fileprivate init() {}
		fileprivate mutating func setResult(type:UInt8, result:_cswiftslash_optr_t?) {
			ron = .result(.success(type, result))
			assPT = pthread_self()
		}
		fileprivate mutating func setError(type:UInt8, error:_cswiftslash_optr_t?) {
			ron = .result(.failure(type, error))
			assPT = pthread_self()
		}
		fileprivate mutating func setNil() {
			ron = .result(nil)
			assPT = pthread_self()
		}
		fileprivate func getResult() throws -> (Result?, pthread_t) {
			switch ron {
				case .noResult:
					throw NoResultAvailable()
				case .result(let res):
					return (res, assPT!)
			}
		}
	}

	fileprivate struct UnexpectedSyncronousThreading:Swift.Error {}
    fileprivate func waitSync() throws -> Result? {
		let mytid = pthread_self()
		var resultPtr = SyncResult()
		withUnsafeMutablePointer(to:&resultPtr) { resultPtrPtr in
			_cswiftslash_future_t_wait_sync(self.futurePtr, resultPtrPtr, Self.futureSyncResultHandler, Self.futureSyncErrorHandler, Self.futureSyncCancelHandler)
		}
		let getr = try resultPtr.getResult()
		guard pthread_equal(mytid, getr.1) != 0 else {
			throw UnexpectedSyncronousThreading()
		}
		return getr.0
    }


	/// Internal handlers that match the C function pointer types
	private static let futureSyncResultHandler:future_result_val_handler_f = { resType, resPtr, ctxPtr in
		ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setResult(type:resType, result:resPtr)
	}

	private static let futureSyncErrorHandler:future_result_err_handler_f = { errType, errPtr, ctxPtr in
		ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setError(type:errType, error:errPtr)
	}

	private static let futureSyncCancelHandler:future_result_cancel_handler_f = { ctxPtr in
		ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setNil()
	}
}

// MARK: - Test Cases