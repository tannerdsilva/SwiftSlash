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
	private let prim:UnsafeMutablePointer<__cswiftslash_future_t>

	/// the deallocator function that this instance will use when it is destroyed.
	private let successDeallocator:SuccessfulResultDeallocator?

	/// creates a new instance of Future.
	/// - parameters:
	/// 	- successfulResultDeallocator: a user defined deallocator function that is called when the future is destroyed and the result is successful. if nil, the result is not have any deallocation work done (assumed to be a swift native type).
	public init(successfulResultDeallocator:consuming SuccessfulResultDeallocator? = nil) {
		prim = __cswiftslash_future_t_init()
		successDeallocator = successfulResultDeallocator
	}

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

	/// wait for the result of the future. specify an error to throw if the current task is canceled.
	/// - parameters:
	///		- throwing: the type of error to throw if the current task is canceled.
	/// 	- taskCancellationError: an autoclosure that returns an error to throw when the current task is canceled. the closure is not called if the task is not canceled.
	/// - returns: a result structure representing the result of the future. `nil` is returned if the future was canceled.
	/// - throws: this function will throw the passed argument from `taskCancellationError` if the current task was canceled while waiting for the result.
	public func result<E>(throwingOnCurrentTaskCancellation taskThrowType:E.Type, taskCancellationError:@autoclosure () -> E) async throws(E) -> Result<R, F>? where E:Swift.Error {
		return try await _result_main(throwing:taskThrowType, onCurrentTaskCancellation:taskCancellationError())
	}

	/// wait for the result of the future. this function will not throw if the current task is canceled.
	/// - returns: a result structure representing the result of the future. `nil` is returned if the future was canceled.
	public func result(throwingOnCurrentTaskCancellation taskThrowType:Never.Type = Never.self) async -> Result<R, F>? {
		return await _result_main(throwing:Never.self, onCurrentTaskCancellation:fatalError("SwiftSlashFuture :: caught trying to create an error to throw within Never type. this is an internal error. \(#file) \(#line)"))
	}

	/// assign a function to be called when the result of the future is known. this function may be fired immediately on the current thread or on a different thread at a later time. 
	/// - parameters:
	/// 	- callback: the function to call when the result is known. this function will be passed nil if the future was canceled.
	/// - returns: the id of the waiter that was created. this id can be used to cancel the waiter. nil is returned if the callback was fired immediately from the current thread.
	@discardableResult public func whenResult(_ callback:consuming @escaping (Result<R, F>?) -> Void) -> UInt64? {
		let asr = AsyncResult(handle: { [cb = callback] res in
			switch res {
				case .success(_, let res):
					cb(.success(Unmanaged<Contained<R>>.fromOpaque(res!).takeUnretainedValue().value()))
				case .failure(_, let res):
					cb(.failure(Unmanaged<Contained<F>>.fromOpaque(res!).takeUnretainedValue().value()))
				case .cancel:
					cb(nil)
			}
		})

		let arPtr = UnsafeMutablePointer<AsyncResult>.allocate(capacity:1)
		arPtr.initialize(to:asr)

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
	@discardableResult public func cancel(waiterID:consuming UInt64) -> Bool {
		return __cswiftslash_future_t_wait_async_invalidate(prim, waiterID)
	}

	/// blocking wait for the result of the future. this is used only for unit testing.
	internal borrowing func blockingResult() -> Result<R, F>? {
		var getResult = SyncResult()
		withUnsafeMutablePointer(to:&getResult) { rptr in
			__cswiftslash_future_t_wait_sync(prim, rptr, futureSyncResultHandler, futureSyncErrorHandler, futureSyncCancelHandler)
		}
		switch getResult.consumeResult()! {
			case .success(_, let res):
				return .success(Unmanaged<Contained<R>>.fromOpaque(res!).takeUnretainedValue().value())
			case .failure(_, let res):
				return .failure(Unmanaged<Contained<F>>.fromOpaque(res!).takeUnretainedValue().value())
			case .cancel:
				return nil
		}
	}
	
	deinit {
		// initialize the tool that will help extract the result from the future
		var deallocResult = SyncResult()

		// destroy the future
		withUnsafeMutablePointer(to:&deallocResult) { rptr in
			__cswiftslash_future_t_destroy(prim, rptr, futureSyncResultHandler, futureSyncErrorHandler)
		}

		// extract the result and deallocate the result
		let extractedResult = deallocResult.consumeResult()
		switch extractedResult {
			case .success(_, let ptr):
				if successDeallocator != nil {
					successDeallocator!(Unmanaged<Contained<R>>.fromOpaque(ptr!).takeRetainedValue().value())
				} else {
					_ = Unmanaged<Contained<R>>.fromOpaque(ptr!).takeRetainedValue()
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
	private borrowing func _result_main<E>(throwing _:E.Type, onCurrentTaskCancellation throwOnTaskCancellation:@autoclosure () -> E) async throws(E) -> Result<R, F>? where E:Swift.Error {
		// allocate space for the result to be stored when it is ready.
		let resultPtr = UnsafeMutablePointer<Result<R, F>?>.allocate(capacity:1)
		resultPtr.initialize(to:nil)
		defer {
			resultPtr.deinitialize(count:1)
			resultPtr.deallocate()
		}

		// initialize the async tool that will allow us to wait for the result and also cancel our waiting if necessary.
		let asr = AsyncResult(handle: { [rp = resultPtr] res in
			switch res {
				case .success(_, let res):
					rp.pointee = .success(Unmanaged<Contained<R>>.fromOpaque(res!).takeUnretainedValue().value())
				case .failure(_, let res):
					rp.pointee = .failure(Unmanaged<Contained<F>>.fromOpaque(res!).takeUnretainedValue().value())
				case .cancel:
					rp.pointee = nil
			}
		})
		let arPtr = UnsafeMutablePointer<AsyncResult>.allocate(capacity:1)
		arPtr.initialize(to:asr)
		
		let waiterID = __cswiftslash_future_t_wait_async(prim, arPtr, futureAsyncResultHandler, futureAsyncErrorHandler, futureAsyncCancelHandler)
		if (waiterID != 0) {
			if E.self == Never.self {
				// task cancellation is set to never throw, so we can just wait for the result.
				await withUnsafeContinuation({ [arp = arPtr] (cont:UnsafeContinuation<Void, Never>) in
					arp.pointee.wait()
					cont.resume()
				})
				return resultPtr.pointee
			} else {
				// task cancellation is set to throw, so we need to wait for the result within a cancellation handler.
				await withTaskCancellationHandler { [arpO = arPtr] in
					await withUnsafeContinuation({ [arpI = arpO] (cont:UnsafeContinuation<Void, Never>) in
						arpI.pointee.wait()
						cont.resume()
					})
				} onCancel: {
					__cswiftslash_future_t_wait_async_invalidate(prim, waiterID)
				}
				if Task.isCancelled == true && resultPtr.pointee == nil {
					throw throwOnTaskCancellation()
				} else {
					return resultPtr.pointee
				}
			}
		} else {
			return resultPtr.pointee
		}
	}
}

// MARK: - Bridging Symbols
fileprivate enum SuccessFailureCancel {
	case success(UInt8, UnsafeMutableRawPointer?)
	case failure(UInt8, UnsafeMutableRawPointer?)
	case cancel
}

/// a reference type that is used to bridge the c future result handlers to strict swift types. c functions cannot be declared or utilized within the context of generic types, so types like this are used to help bridge the C functions into strict Swift typing.
fileprivate final class AsyncResult:@unchecked Sendable {
	fileprivate typealias UniHandler = (SuccessFailureCancel) -> Void
	
	private let internalStateMutex:UnsafeMutablePointer<pthread_mutex_t>
	
	private let resultMutex:UnsafeMutablePointer<pthread_mutex_t>
	private let isResultMutexLocked:UnsafeMutablePointer<__cswiftslash_atomic_uint8_t>

	private let uniHandler:UnsafeMutablePointer<UniHandler?>

	fileprivate init(handle:consuming @escaping UniHandler) {
		internalStateMutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity:1) // this is expected to deallocate with the lifecycle of the containing class.
		internalStateMutex.initialize(to:pthread_mutex_t())
		pthread_mutex_init(internalStateMutex, nil)

		resultMutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity:1)
		resultMutex.initialize(to:pthread_mutex_t())
		pthread_mutex_init(resultMutex, nil)

		isResultMutexLocked = UnsafeMutablePointer<__cswiftslash_atomic_uint8_t>.allocate(capacity:1)
		isResultMutexLocked.initialize(to:__cswiftslash_auint8_init(1))
		pthread_mutex_lock(resultMutex)

		uniHandler = UnsafeMutablePointer<UniHandler?>.allocate(capacity:1)
		uniHandler.initialize(to:handle)
	}
	fileprivate borrowing func setResult(type:consuming UInt8, pointer:consuming UnsafeMutableRawPointer?) {
		pthread_mutex_lock(internalStateMutex)
		defer {
			pthread_mutex_unlock(internalStateMutex)
		}
		var expected:UInt8 = 1
		if __cswiftslash_auint8_compare_exchange_weak(isResultMutexLocked, &expected, 0) {
			pthread_mutex_unlock(resultMutex)
			uniHandler.pointee!(.success(type, pointer))
			uniHandler.pointee = nil
		}
	}
	fileprivate borrowing func setError(type:consuming UInt8, pointer:consuming UnsafeMutableRawPointer?) {
		pthread_mutex_lock(internalStateMutex)
		defer {
			pthread_mutex_unlock(internalStateMutex)
		}
		var expected:UInt8 = 1
		if __cswiftslash_auint8_compare_exchange_weak(isResultMutexLocked, &expected, 0) {
			pthread_mutex_unlock(resultMutex)
			uniHandler.pointee!(.failure(type, pointer))
			uniHandler.pointee = nil
		}
	}
	fileprivate borrowing func setCancel() {
		pthread_mutex_lock(internalStateMutex)
		defer {
			pthread_mutex_unlock(internalStateMutex)
		}
		var expected:UInt8 = 1
		if __cswiftslash_auint8_compare_exchange_weak(isResultMutexLocked, &expected, 0) {
			pthread_mutex_unlock(resultMutex)
			uniHandler.pointee!(.cancel)
			uniHandler.pointee = nil
		}
	}
	fileprivate borrowing func wait() {
		pthread_mutex_lock(internalStateMutex)
		if __cswiftslash_auint8_load(isResultMutexLocked) == 1 {
			pthread_mutex_unlock(internalStateMutex)
			pthread_mutex_lock(resultMutex)
			pthread_mutex_lock(internalStateMutex)
			pthread_mutex_unlock(resultMutex)
		}
		pthread_mutex_unlock(internalStateMutex)
	}

	deinit {
		pthread_mutex_destroy(internalStateMutex)

		internalStateMutex.deinitialize(count:1)
		internalStateMutex.deallocate()

		if __cswiftslash_auint8_load(isResultMutexLocked) == 1 {
			pthread_mutex_unlock(resultMutex)
		}

		pthread_mutex_destroy(resultMutex)
		resultMutex.deinitialize(count:1)
		resultMutex.deallocate()

		isResultMutexLocked.deinitialize(count:1)
		isResultMutexLocked.deallocate()

		uniHandler.deinitialize(count:1)
		uniHandler.deallocate()
	}
}

// internal tool to help extract the result from the future in a synchronous manner.
fileprivate struct SyncResult:~Copyable {
	private var result:SuccessFailureCancel? = nil
	fileprivate init() {}
	fileprivate mutating func setResult(type:UInt8, pointer:UnsafeMutableRawPointer?) {
		result = .success(type, pointer)
	}
	fileprivate mutating func setError(type:UInt8, pointer:UnsafeMutableRawPointer?) {
		result = .failure(type, pointer)
	}
	fileprivate mutating func setCancel() {
		result = .cancel
	}
	fileprivate consuming func consumeResult() -> SuccessFailureCancel? {
		return result
	}
}

// MARK: - Sync C Handlers
/// the sync handler for results
fileprivate let futureSyncResultHandler:__cswiftslash_future_result_val_handler_f = { resType, resPtr, ctxPtr in
	ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setResult(type:resType, pointer:resPtr)
}
/// the sync handler for errors
fileprivate let futureSyncErrorHandler:__cswiftslash_future_result_err_handler_f = { errType, errPtr, ctxPtr in
	ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setError(type:errType, pointer:errPtr)
}
/// the sync handler for cancellations
fileprivate let futureSyncCancelHandler:__cswiftslash_future_result_cncl_handler_f = { ctxPtr in
	ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setCancel()
}

// MARK: - Async C Handlers
/// the async handler for results
fileprivate let futureAsyncResultHandler:__cswiftslash_future_result_val_handler_f = { resType, resPtr, ctxPtr in
	let boundPtr = ctxPtr!.assumingMemoryBound(to:AsyncResult.self)
	boundPtr.pointee.setResult(type:resType, pointer:resPtr)
	boundPtr.deinitialize(count:1)
	boundPtr.deallocate()
}
/// the async handler for errors
fileprivate let futureAsyncErrorHandler:__cswiftslash_future_result_err_handler_f = { errType, errPtr, ctxPtr in
	let boundPtr = ctxPtr!.assumingMemoryBound(to:AsyncResult.self)
	boundPtr.pointee.setError(type:errType, pointer:errPtr)
	boundPtr.deinitialize(count:1)
	boundPtr.deallocate()
}
/// the async handler for cancellations
fileprivate let futureAsyncCancelHandler:__cswiftslash_future_result_cncl_handler_f = { ctxPtr in
	let boundPtr = ctxPtr!.assumingMemoryBound(to:AsyncResult.self)
	boundPtr.pointee.setCancel()
	boundPtr.deinitialize(count:1)
	boundPtr.deallocate()
}