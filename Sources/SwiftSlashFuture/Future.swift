/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_future
import SwiftSlashContained
import __cswiftslash_auint8

/// thrown when a result is set on a future that is already set.
public struct InvalidStateError:Swift.Error {}

/// a reference type that represents a result that will be available in the future.
public final class Future<R, F>:@unchecked Sendable where F:Swift.Error {

	/// the type that is contained within the future.
	public typealias SuccessfulResultDeallocator = (R) -> Void

	/// the underlying c primitive that this future wraps.
	internal let prim:UnsafeMutablePointer<__cswiftslash_future_t>

	/// the deallocator function that this instance will use when it is destroyed.
	private let successDeallocator:SuccessfulResultDeallocator?

	/// creates a new instance of Future.
	/// - parameters:
	/// 	- successfulResultDeallocator: a user defined deallocator function that is called when the future is destroyed and the result is successful. if nil, the result is not have any deallocation work done (assumed to be a swift native type).
	public init(successfulResultDeallocator:consuming SuccessfulResultDeallocator? = nil) {
		prim = __cswiftslash_future_t_init()
		successDeallocator = successfulResultDeallocator
	}

	deinit {
		// initialize the tool that will help extract the result from the future
		var deallocResult = SyncResult()

		// destroy the future
		withUnsafeMutablePointer(to:&deallocResult) { rptr in
			__cswiftslash_future_t_destroy(prim, rptr, futureSyncResultHandler, futureSyncErrorHandler)
		}

		// extract the result and deallocate the result that
		let extractedResult = deallocResult.consumeResult()
		switch extractedResult {
			case .success(_, let ptr):
				let rv = Unmanaged<Contained<R>>.fromOpaque(ptr!).takeRetainedValue()
				if successDeallocator != nil {
					// the retained value must be passed to the success deallocator
					successDeallocator!(rv.value())
				}
			case .failure(_, let ptr):
				_ = Unmanaged<Contained<F>>.fromOpaque(ptr!).takeRetainedValue()
			case .cancel:
				fatalError("future was canceled within deallocation block. this is an internal error. \(#file) \(#line)")
			case .none:
				break
		}
	}
}

extension Future {

	/// assign a successful result to the future.
	/// - parameters:
	/// 	- result: the result to assign to the future.
	/// - throws: InvalidStateError if the future is already set with a result or error.
	public func setSuccess(_ result:consuming R) throws(InvalidStateError) {
		let op = Unmanaged.passRetained(Contained(result)).toOpaque()
		guard __cswiftslash_future_t_broadcast_res_val(prim, 1, op) else {
			_ = Unmanaged<Contained<R>>.fromOpaque(op).takeRetainedValue()
			throw InvalidStateError()
		}
	}

	/// assign a failure to the future.
	/// - parameters:
	/// 	- error: the error to assign to the future.
	/// - throws: InvalidStateError if the future is already set with a result or error.
	public func setFailure(_ error:consuming F) throws(InvalidStateError) {
		let op = Unmanaged.passRetained(Contained(error)).toOpaque()
		guard __cswiftslash_future_t_broadcast_res_throw(prim, 1, op) else {
			_ = Unmanaged<Contained<F>>.fromOpaque(op).takeRetainedValue()
			throw InvalidStateError()
		}
	}

	/// cancel an active future.
	/// - throws: InvalidStateError if the future is already set with a result or error.
	public func cancel() throws(InvalidStateError) {
		guard __cswiftslash_future_t_broadcast_cancel(prim) else {
			throw InvalidStateError()
		}
	}
}

extension Future {

	/// wait for the result of the future. specify an error to throw if the current task is canceled.
	/// - parameters:
	///		- throwing: the type of error to throw if the current task is canceled.
	/// 	- taskCancellationError: an autoclosure that returns an error to throw when the current task is canceled. the closure is not called if the task is not canceled.
	/// - returns: a result structure representing the result of the future. `nil` is returned if the future was canceled.
	/// - throws: this function will run the @autoclosure argument from `taskCancellationError` and throw the corresponding result if the current task was canceled while waiting for the result.
	public func result<E>(throwingOnCurrentTaskCancellation taskThrowType:E.Type, taskCancellationError:@autoclosure () -> E) async throws(E) -> Result<R, F>? where E:Swift.Error {
		return try await _result_main(throwing:taskThrowType, onCurrentTaskCancellation:taskCancellationError())
	}

	/// wait for the result of the future. this function will not throw if the current task is canceled.
	/// - throws: this function does NOT throw.
	/// - returns: a result structure representing the result of the future. `nil` is returned if the future was canceled.
	public func result(throwingOnCurrentTaskCancellation taskThrowType:Never.Type = Never.self) async -> Result<R, F>? {
		return await _result_main(throwing:Never.self, onCurrentTaskCancellation:fatalError("SwiftSlashFuture :: caught trying to create an error to throw within Never type. this is an internal error. \(#file) \(#line)"))
	}

	/// assign a function to be called when the result of the future is known. this function may be fired immediately on the current thread or on a different thread at a later time. 
	/// - parameters:
	/// 	- callback: the function to call when the result is known. this function will be passed nil if the future was canceled.
	/// - returns: the id of the waiter that was created. this id can be used to cancel the waiter. nil is returned if the callback was fired immediately from the current thread.
	@discardableResult public func whenResult(_ callback:consuming @escaping (Result<R, F>?) -> Void) -> UInt64? {
		// define the async result here so that it will remain in memory for at least the duration of the function call.
		let asr = AsyncResult(storage:nil, handle: { [cb = callback] res, _ in
			switch res {
				case .success(_, let res):
					cb(.success(Unmanaged<Contained<R>>.fromOpaque(res!).takeUnretainedValue().value()))
				case .failure(_, let res):
					cb(.failure(Unmanaged<Contained<F>>.fromOpaque(res!).takeUnretainedValue().value()))
				case .cancel:
					cb(nil)
			}
		})
		// copy a reference of the async result handler to new heap space so that the c code can interact with it and dereference it as needed.
		let arPtr = UnsafeMutablePointer<AsyncResult>.allocate(capacity:1)
		arPtr.initialize(to:asr)
		// register the async handlers for the waiter of this future.
		let waitID = __cswiftslash_future_t_wait_async(prim, arPtr, futureAsyncResultHandler, futureAsyncErrorHandler, futureAsyncCancelHandler)
		if waitID == 0 {
			return nil
		} else {
			return waitID
		}
	}

	/// cancel a waiter that was created with `whenResult`.
	/// - parameters:
	/// 	- waiterID: the id of the waiter to cancel.
	@discardableResult public func cancelWaiter(_ waiterID:consuming UInt64) -> Bool {
		return __cswiftslash_future_t_wait_async_invalidate(prim, waiterID)
	}
}

extension Future {
	fileprivate borrowing func _result_main<E>(throwing _:E.Type, onCurrentTaskCancellation throwOnTaskCancellation:@autoclosure () -> E) async throws(E) -> Result<R, F>? where E:Swift.Error {
		// allocate space for the result to be stored when it is ready.
		let resultPtr = UnsafeMutablePointer<Result<R, F>?>.allocate(capacity:1)
		resultPtr.initialize(to:nil)
		defer {
			resultPtr.deinitialize(count:1)
			resultPtr.deallocate()
		}

		// initialize the async tool that will allow us to wait for the result and also cancel our waiting if necessary.
		let asr = AsyncResult(storage:resultPtr, handle: { res, rp in
			switch res {
				case .success(_, let res):
					rp!.assumingMemoryBound(to:Result<R, F>?.self).pointee = .success(Unmanaged<Contained<R>>.fromOpaque(res!).takeUnretainedValue().value())
				case .failure(_, let res):
					rp!.assumingMemoryBound(to:Result<R, F>?.self).pointee = .failure(Unmanaged<Contained<F>>.fromOpaque(res!).takeUnretainedValue().value())
				case .cancel:
					rp!.assumingMemoryBound(to:Result<R, F>?.self).pointee = nil
			}
		})

		// copy a reference of the asyncresult to heap so that the c primitive can interact it and free its reference when it is done.
		let arPtr = UnsafeMutablePointer<AsyncResult>.allocate(capacity:1)
		arPtr.initialize(to:asr)
		
		let waiterID = __cswiftslash_future_t_wait_async(prim, arPtr, futureAsyncResultHandler, futureAsyncErrorHandler, futureAsyncCancelHandler)
		if (waiterID != 0) {
			if E.self == Never.self {
				// task cancellation is set to never throw, so we can just wait for the result directly from the AsyncResult.
				return await arPtr.pointee.wait(loadingAs:Result<R, F>?.self)
			} else {
				// task cancellation is set to throw, so we need to wait for the result within a cancellation handler.
				let returnResult = await withTaskCancellationHandler { [arpO = arPtr] in
					return await arpO.pointee.wait(loadingAs:Result<R, F>?.self)
				} onCancel: {
					__cswiftslash_future_t_wait_async_invalidate(prim, waiterID)
				}
				if Task.isCancelled == true && returnResult == nil {
					throw throwOnTaskCancellation()
				} else {
					return returnResult
				}
			}
		} else {
			return resultPtr.pointee
		}
	}
}