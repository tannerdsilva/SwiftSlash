/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_future
import SwiftSlashContained
import Synchronization

/// thrown when a result is set on a future that is already set.
public struct InvalidFutureStateError:Swift.Error {}

/// a reference type that represents a result that will be available in the future.
public final class Future<Produced, Failure>:@unchecked Sendable where Failure:Swift.Error {

	/// the type that is contained within the future.
	public typealias SuccessfulResultDeallocator = (Produced) -> Void

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
				let rv = Unmanaged<Contained<Produced>>.fromOpaque(ptr!).takeRetainedValue()
				if successDeallocator != nil {
					// the retained value must be passed to the success deallocator
					successDeallocator!(rv.value())
				}
			case .failure(_, let ptr):
				_ = Unmanaged<Contained<Failure>>.fromOpaque(ptr!).takeRetainedValue()
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
	public func setSuccess(_ result:consuming Produced) throws(InvalidFutureStateError) {
		let op = Unmanaged.passRetained(Contained(result)).toOpaque()
		guard __cswiftslash_future_t_broadcast_res_val(prim, 1, op) else {
			_ = Unmanaged<Contained<Produced>>.fromOpaque(op).takeRetainedValue()
			throw InvalidFutureStateError()
		}
	}

	/// assign a failure to the future.
	/// - parameters:
	/// 	- error: the error to assign to the future.
	/// - throws: InvalidStateError if the future is already set with a result or error.
	public func setFailure(_ error:consuming Failure) throws(InvalidFutureStateError) {
		let op = Unmanaged.passRetained(Contained(error)).toOpaque()
		guard __cswiftslash_future_t_broadcast_res_throw(prim, 1, op) else {
			_ = Unmanaged<Contained<Failure>>.fromOpaque(op).takeRetainedValue()
			throw InvalidFutureStateError()
		}
	}

	/// cancel an active future.
	/// - throws: InvalidStateError if the future is already set with a result or error.
	public func cancel() throws(InvalidFutureStateError) {
		guard __cswiftslash_future_t_broadcast_cancel(prim) else {
			throw InvalidFutureStateError()
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
	public func result<ErrorOnTaskCancel>(throwingOnCurrentTaskCancellation taskThrowType:ErrorOnTaskCancel.Type, taskCancellationError:@autoclosure () -> ErrorOnTaskCancel) async throws(ErrorOnTaskCancel) -> Result<Produced, Failure>? where ErrorOnTaskCancel:Swift.Error {
		var syncResult = SyncResult()
		var memory = __cswiftslash_future_wait_t_init_struct()
		return try await _result_main(throwing:taskThrowType, onCurrentTaskCancellation:taskCancellationError(), memory:&memory, syncResult:&syncResult)
	}

	/// wait for the result of the future. this function will not throw if the current task is canceled.
	/// - throws: this function does NOT throw.
	/// - returns: a result structure representing the result of the future. `nil` is returned if the future was canceled.
	public func result(throwingOnCurrentTaskCancellation taskThrowType:Never.Type = Never.self) async -> Result<Produced, Failure>? {
		var syncResult = SyncResult()
		var memory = __cswiftslash_future_wait_t_init_struct()
		return await _result_main(throwing:Never.self, onCurrentTaskCancellation:fatalError("SwiftSlashFuture :: caught trying to create an error to throw within Never type. this is an internal error. \(#file):\(#line)"), memory:&memory, syncResult:&syncResult)
	}

	/// assign a function to be called when the result of the future is known. this function may be fired immediately on the current thread or on a different thread at a later time. 
	/// - parameters:
	/// 	- callback: the function to call when the result is known. this function will be passed nil if the future was canceled.
	/// - returns: the id of the waiter that was created. this id can be used to cancel the waiter. nil is returned if the callback was fired immediately from the current thread.
	@discardableResult public func whenResult(_ callback:consuming @escaping @Sendable (Result<Produced, Failure>?) -> Void) -> UInt64? {
		// define the async result here so that it will remain in memory for at least the duration of the function call.
		let asr = AsyncResult(handle: { [cb = callback] res in
			switch res {
				case .success(_, let res):
					cb(.success(Unmanaged<Contained<Produced>>.fromOpaque(res!).takeUnretainedValue().value()))
				case .failure(_, let res):
					cb(.failure(Unmanaged<Contained<Failure>>.fromOpaque(res!).takeUnretainedValue().value()))
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
	fileprivate borrowing func _result_main<E>(throwing _:E.Type, onCurrentTaskCancellation throwOnTaskCancellation:@autoclosure () -> E, memory:UnsafeMutablePointer<__cswiftslash_future_wait_t>, syncResult sPtr:UnsafeMutablePointer<SyncResult>) async throws(E) -> Result<Produced, Failure>? where E:Swift.Error {
		return try await sPtr.pointee.withWaiterPrimitiveAccess { wptr throws(E) -> Result<Produced, Failure>? in
			let waiterPtr = __cswiftslash_future_t_wait_sync_register(prim, sPtr, futureSyncResultHandler, futureSyncErrorHandler, futureSyncCancelHandler, memory)
			if waiterPtr == nil {
				switch sPtr.pointee.consumeResult() {
					case .success(_, let ptr):
						return .success(Unmanaged<Contained<Produced>>.fromOpaque(ptr!).takeUnretainedValue().value())
					case .failure(_, let ptr):
						return .failure(Unmanaged<Contained<Failure>>.fromOpaque(ptr!).takeUnretainedValue().value())
					case .cancel:
						return nil
					case .none:
						fatalError("invalid future status. this is an internal error. \(#file):\(#line)")
				}
			} else {
				if E.self == Never.self {
					// task cancellation is set to never throw, so we can just wait for the result directly from the AsyncResult.
					await withUnsafeContinuation({ (cont:UnsafeContinuation<Void, Never>) in
						__cswiftslash_future_t_wait_sync_block(prim, waiterPtr!)
						cont.resume()
					})

					switch sPtr.pointee.consumeResult() {
						case .success(_, let ptr):
							return .success(Unmanaged<Contained<Produced>>.fromOpaque(ptr!).takeUnretainedValue().value())
						case .failure(_, let ptr):
							return .failure(Unmanaged<Contained<Failure>>.fromOpaque(ptr!).takeUnretainedValue().value())
						case .cancel:
							return nil
						case .none:
							fatalError("invalid future status. this is an internal error. \(#file):\(#line)")
					}
				} else {
					let cancelID = __cswiftslash_future_wait_id_get(waiterPtr!)

					let didCallCancellationHandler:Atomic<Bool> = .init(false)

					// task cancellation is set to throw, so we need to wait for the result within a cancellation handler.
					await withTaskCancellationHandler {
						await withUnsafeContinuation({ (cont:UnsafeContinuation<Void, Never>) in
							__cswiftslash_future_t_wait_sync_block(prim, waiterPtr!)
							cont.resume()
						})
					} onCancel: {
						didCallCancellationHandler.store(true, ordering:.releasing)
						__cswiftslash_future_wait_sync_invalidate(prim, cancelID)
					}

					switch sPtr.pointee.consumeResult() {
						case .success(_, let ptr):
							return .success(Unmanaged<Contained<Produced>>.fromOpaque(ptr!).takeUnretainedValue().value())
						case .failure(_, let ptr):
							return .failure(Unmanaged<Contained<Failure>>.fromOpaque(ptr!).takeUnretainedValue().value())
						case .cancel:
							if didCallCancellationHandler.load(ordering:.acquiring) {
								throw throwOnTaskCancellation()
							} else {
								return nil
							}
						case .none:
							fatalError("invalid future status. this is an internal error. \(#file):\(#line)")
					}
				}
			}
		}
	}		
}
