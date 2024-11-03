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
	public func cancel() throws(InvalidStateError){
		guard __cswiftslash_future_t_broadcast_cancel(prim) else {
			throw InvalidStateError()
		}
	}


	/// wait for the result of the future. specify an error to throw if the current task is canceled.
	/// - parameters:
	/// 	- taskCancellationError: an autoclosure that returns an error to throw when the current task is canceled. the closure is not called if the task is not canceled.
	/// - returns: a result structure representing the result of the future.
	/// - throws: this function will throw the passed argument from `taskCancellationError` if the current task was canceled while waiting for the result.
	public func result<CE>(taskCancellationError throwOnTaskCancellation:@autoclosure () -> CE) async throws(CE) -> Result<R, F> where CE:Swift.Error {
		// allocate space for the result to be stored when it is ready.
		let resultPtr = UnsafeMutablePointer<Result<R, F>?>.allocate(capacity:1)
		resultPtr.initialize(to:nil)
		defer {
			resultPtr.deinitialize(count:1)
			resultPtr.deallocate()
		}

		// initialize the async tool that will allow us to wait for the result and also cancel our waiting if necessary.
		let arPtr = UnsafeMutablePointer<AsyncResult>.allocate(capacity:1)
		arPtr.initialize(to:AsyncResult(handler: { res in
			switch res {
				case .success(let res):
					resultPtr.pointee = .success(Unmanaged<Contained<R>>.fromOpaque(res.1!).takeUnretainedValue().value())
				case .failure(let err):
					resultPtr.pointee = .failure(Unmanaged<Contained<F>>.fromOpaque(err.1!).takeUnretainedValue().value())
				case .cancel:
					resultPtr.pointee = nil
			}
		}))
		
		let waiterID = __cswiftslash_future_t_wait_async(prim, arPtr, futureAsyncResultHandler, futureAsyncErrorHandler, futureAsyncCancelHandler)
		if (waiterID != 0) {
			// wait for the result to be set. this is basically a synchronous wait but it happens within a continuation block.
			await withTaskCancellationHandler { [arp = arPtr] in
				await withUnsafeContinuation({ [arp = arp] (cont:UnsafeContinuation<Void, Never>) in
					arp.pointee.wait()
					cont.resume()
				})
			} onCancel: {
				__cswiftslash_future_t_wait_async_invalidate(prim, waiterID)
			}
		}
		if resultPtr.pointee == nil {
			throw throwOnTaskCancellation()
		} else {
			return resultPtr.pointee!
		}
	}

	/// wait for the result of the future. this function does not respond to task cancellation.
	/// - parameters:
	/// 	- taskCancellationError: the error to throw if the current task is canceled.
	/// - returns: a result structure representing the result of the future.
	public func result() async -> Result<R, F>? {
		// allocate space for the result to be stored when it is ready.
		let resultPtr = UnsafeMutablePointer<Result<R, F>?>.allocate(capacity:1)
		resultPtr.initialize(to:nil)
		defer {
			resultPtr.deinitialize(count:1)
			resultPtr.deallocate()
		}

		// initialize the async tool that will allow us to wait for the result and also cancel our waiting if necessary.
		let arPtr = UnsafeMutablePointer<AsyncResult>.allocate(capacity:1)
		arPtr.initialize(to:AsyncResult(handler: { res in
			switch res {
				case .success(let res):
					resultPtr.pointee = .success(Unmanaged<Contained<R>>.fromOpaque(res.1!).takeUnretainedValue().value())
				case .failure(let err):
					resultPtr.pointee = .failure(Unmanaged<Contained<F>>.fromOpaque(err.1!).takeUnretainedValue().value())
				case .cancel:
					resultPtr.pointee = nil
			}
		}))
		// no defer block needed here. the async tool will be deallocated when the result is set.
		
		let waiterID = __cswiftslash_future_t_wait_async(prim, arPtr, futureAsyncResultHandler, futureAsyncErrorHandler, futureAsyncCancelHandler)
		if (waiterID != 0) {
			await withUnsafeContinuation({ [arp = arPtr] (cont:UnsafeContinuation<Void, Never>) in
				arp.pointee.wait()
				cont.resume()
			})
		}
		return resultPtr.pointee
	}

	/// assign a function to be called when the result of the future is known. this function may be fired immediately on the current thread or on a different thread at a later time. 
	/// - parameters:
	/// 	- callback: the function to call when the result is known. this function will be passed nil if the future was canceled.
	@discardableResult public func whenResult(_ callback:@escaping (Result<R, F>?) -> Void) -> UInt64? {
		let arPtr = UnsafeMutablePointer<AsyncResult>.allocate(capacity:1)
		arPtr.initialize(to:AsyncResult(handler: { [cb = callback] res in
			switch res {
				case .success(let res):
					cb(.success(Unmanaged<Contained<R>>.fromOpaque(res.1!).takeUnretainedValue().value()))
				case .failure(let err):
					cb(.failure(Unmanaged<Contained<F>>.fromOpaque(err.1!).takeUnretainedValue().value()))
				case .cancel:
					cb(nil)
			}
		}))
		let waitID = __cswiftslash_future_t_wait_async(prim, arPtr, futureAsyncResultHandler, futureAsyncErrorHandler, futureAsyncCancelHandler)
		if waitID == 0 {
			return nil
		} else {
			return waitID
		}
	}

	/// cancel a waiting future.
	/// - parameters:
	/// 	- waiterID: the id of the waiter to cancel.
	public func cancel(waiterID:UInt64) {
		__cswiftslash_future_t_wait_async_invalidate(prim, waiterID)
	}

	/// blocking wait for the result of the future. this is used only for unit testing.
	internal borrowing func blockingResult() -> Result<R, F>? {
		var getResult = SyncResult()
		withUnsafeMutablePointer(to:&getResult) { rptr in
			__cswiftslash_future_t_wait_sync(prim, rptr, futureSyncResultHandler, futureSyncErrorHandler, futureSyncCancelHandler)
		}
		switch getResult.getResult() {
			case .success(let res):
				return .success(Unmanaged<Contained<R>>.fromOpaque(res.1!).takeUnretainedValue().value())
			case .failure(let res):
				return .failure(Unmanaged<Contained<F>>.fromOpaque(res.1!).takeUnretainedValue().value())
			case .cancel:
				return nil
		}
	}
	
	deinit {
		// initialize the tool that will help extract the result from the future
		var deallocResult = DeallocateTool()

		// destroy the future
		withUnsafeMutablePointer(to:&deallocResult) { rptr in
			__cswiftslash_future_t_destroy(prim, rptr, futureResultDeallocator, futureErrorDeallocator)
		}

		// extract the result and deallocate the result
		let extractedResult = deallocResult.extractState()
		switch extractedResult {
			case .success(_, let ptr):
				if successDeallocator != nil {
					successDeallocator!(Unmanaged<Contained<R>>.fromOpaque(ptr!).takeRetainedValue().value())
				} else {
					_ = Unmanaged<Contained<R>>.fromOpaque(ptr!).takeRetainedValue()
				}
			case .failure(_, let ptr):
				_ = Unmanaged<Contained<F>>.fromOpaque(ptr!).takeRetainedValue()
			case .none:
				break
		}
	}
}

// MARK: - Bridging Symbols

// the underlying c primitive that this future wraps can result in one of three states: success, failure, or cancel.
fileprivate enum SuccessFailureCancel<S, F> {
	case success(S)
	case failure(F)
	case cancel
}

extension SuccessFailureCancel where F:Swift.Error {
	fileprivate func asResult() -> Result<S, F>? {
		switch self {
			case .success(let s):
				return .success(s)
			case .failure(let err):
				return .failure(err)
			case .cancel:
				return nil
		}
	}
}

/// a tool to help claim the result (or error) pointers that are stored in the future at deallocation time.
fileprivate struct DeallocateTool:~Copyable {

	/// used to convey the state that was returned from the deallocation function. there may be 
	fileprivate enum State {
		/// indicates that the future was set with a successful result.
		case success(UInt8, UnsafeMutableRawPointer?)
		/// indicates that the future was set with an error.
		case failure(UInt8, UnsafeMutableRawPointer?)
	}

	/// the state that was extracted from the future.
	private var extractedState:State? = nil

	fileprivate init() {}

	/// set to result state.
	fileprivate mutating func setResult(type:UInt8, pointer:UnsafeMutableRawPointer?) {
		extractedState = .success(type, pointer)
	}
	/// set to error state.
	fileprivate mutating func setError(type:UInt8, pointer:UnsafeMutableRawPointer?) {
		extractedState = .failure(type, pointer)
	}
	/// set to cancel state.
	fileprivate consuming func extractState() -> State? {
		return extractedState
	}
}

/// a reference type that is used to bridge the c future result handlers to strict swift types. c functions cannot be declared or utilized within the context of generic types, so types like this are used to help bridge the C functions into strict Swift typing.
fileprivate final class AsyncResult:@unchecked Sendable {
	fileprivate typealias ResultHandler = (SuccessFailureCancel<(UInt8, UnsafeMutableRawPointer?), (UInt8, UnsafeMutableRawPointer?)>) -> Void
	
	private let handler:UnsafeMutablePointer<ResultHandler?>
	private let mutex:UnsafeMutablePointer<pthread_mutex_t>
	
	private let resultMutex:UnsafeMutablePointer<pthread_mutex_t>
	private let isResultMutexLocked:UnsafeMutablePointer<__cswiftslash_atomic_uint8_t>

	fileprivate init(handler h:@escaping (SuccessFailureCancel<(UInt8, UnsafeMutableRawPointer?), (UInt8, UnsafeMutableRawPointer?)>) -> Void) {
		handler = UnsafeMutablePointer<ResultHandler?>.allocate(capacity:1) // this is expected to deallocate with the lifecycle of the containing class.
		handler.initialize(to:h)

		mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity:1) // this is expected to deallocate with the lifecycle of the containing class.
		mutex.initialize(to:pthread_mutex_t())
		pthread_mutex_init(mutex, nil)

		resultMutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity:1)
		resultMutex.initialize(to:pthread_mutex_t())
		pthread_mutex_init(resultMutex, nil)

		isResultMutexLocked = UnsafeMutablePointer<__cswiftslash_atomic_uint8_t>.allocate(capacity:1)
		isResultMutexLocked.initialize(to:__cswiftslash_auint8_init(1))
		pthread_mutex_lock(resultMutex)
	}
	fileprivate func setResult(type:UInt8, pointer:UnsafeMutableRawPointer?) {
		pthread_mutex_lock(mutex)
		var expected:UInt8 = 1
		if __cswiftslash_auint8_compare_exchange_weak(isResultMutexLocked, &expected, 0) {
			pthread_mutex_unlock(resultMutex)
			handler.pointee!(.success((type, pointer)))
			handler.pointee = nil
		}
		pthread_mutex_unlock(mutex)
	}
	fileprivate func setError(type:UInt8, pointer:UnsafeMutableRawPointer?) {
		pthread_mutex_lock(mutex)
		var expected:UInt8 = 1
		if __cswiftslash_auint8_compare_exchange_weak(isResultMutexLocked, &expected, 0) {
			pthread_mutex_unlock(resultMutex)
			handler.pointee!(.failure((type, pointer)))
			handler.pointee = nil
		}
		pthread_mutex_unlock(mutex)
	}
	fileprivate func setCancel() {
		pthread_mutex_lock(mutex)
		var expected:UInt8 = 1
		if __cswiftslash_auint8_compare_exchange_weak(isResultMutexLocked, &expected, 0) {
			pthread_mutex_unlock(resultMutex)
			handler.pointee!(.cancel)
			handler.pointee = nil
		}
		pthread_mutex_unlock(mutex)
	}
	fileprivate func wait() {
		pthread_mutex_lock(mutex)
		if __cswiftslash_auint8_load(isResultMutexLocked) == 1 {
			pthread_mutex_unlock(mutex)
			pthread_mutex_lock(resultMutex)
			pthread_mutex_lock(mutex)
			pthread_mutex_unlock(resultMutex)
		}
		pthread_mutex_unlock(mutex)
	}
	deinit {
		#if DEBUG
		guard handler.pointee == nil else {
			fatalError("swiftslash - async result handler was not called - \(#file):\(#line)")
		}
		#endif
		pthread_mutex_destroy(mutex)

		mutex.deinitialize(count:1)
		mutex.deallocate()
		
		handler.deinitialize(count:1)
		handler.deallocate()

		if __cswiftslash_auint8_load(isResultMutexLocked) == 1 {
			pthread_mutex_unlock(resultMutex)
		}
		pthread_mutex_destroy(resultMutex)
		resultMutex.deinitialize(count:1)
		resultMutex.deallocate()

		isResultMutexLocked.deinitialize(count:1)
		isResultMutexLocked.deallocate()
	}
}

// internal tool to help extract the result from the future in a synchronous manner.
fileprivate struct SyncResult:~Copyable {
	private var result:SuccessFailureCancel<(UInt8, UnsafeMutableRawPointer?), (UInt8, UnsafeMutableRawPointer?)>? = nil
	fileprivate init() {}
	fileprivate mutating func setResult(type:UInt8, pointer:UnsafeMutableRawPointer?) {
		result = .success((type, pointer))
	}
	fileprivate mutating func setError(type:UInt8, pointer:UnsafeMutableRawPointer?) {
		result = .failure((type, pointer))
	}
	fileprivate mutating func setCancel() {
		result = .cancel
	}
	fileprivate consuming func getResult() -> SuccessFailureCancel<(UInt8, UnsafeMutableRawPointer?), (UInt8, UnsafeMutableRawPointer?)> {
		return result!
	}
}

// the result deallocator for futures
fileprivate let futureResultDeallocator:__cswiftslash_future_result_val_handler_f = { resType, resPtr, ctxPtr in
	ctxPtr!.assumingMemoryBound(to:DeallocateTool.self).pointee.setResult(type:resType, pointer:resPtr)
}
// the error deallocator for futures
fileprivate let futureErrorDeallocator:__cswiftslash_future_result_err_handler_f = { errType, errPtr, ctxPtr in
	ctxPtr!.assumingMemoryBound(to:DeallocateTool.self).pointee.setError(type:errType, pointer:errPtr)
}

// the sync handler for results
fileprivate let futureSyncResultHandler:__cswiftslash_future_result_val_handler_f = { resType, resPtr, ctxPtr in
	ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setResult(type:resType, pointer:resPtr)
}
// the sync handler for errors
fileprivate let futureSyncErrorHandler:__cswiftslash_future_result_err_handler_f = { errType, errPtr, ctxPtr in
	ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setError(type:errType, pointer:errPtr)
}
// the sync handler for cancellations
fileprivate let futureSyncCancelHandler:__cswiftslash_future_result_cncl_handler_f = { ctxPtr in
	ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setCancel()
}

// the async handler for results
fileprivate let futureAsyncResultHandler:__cswiftslash_future_result_val_handler_f = { resType, resPtr, ctxPtr in
	let boundPtr = ctxPtr!.assumingMemoryBound(to:AsyncResult.self)
	boundPtr.pointee.setResult(type:resType, pointer:resPtr)
	boundPtr.deinitialize(count:1)
	boundPtr.deallocate()
}
// the async handler for errors
fileprivate let futureAsyncErrorHandler:__cswiftslash_future_result_err_handler_f = { errType, errPtr, ctxPtr in
	let boundPtr = ctxPtr!.assumingMemoryBound(to:AsyncResult.self)
	boundPtr.pointee.setError(type:errType, pointer:errPtr)
	boundPtr.deinitialize(count:1)
	boundPtr.deallocate()
}
// the async handler for cancellations
fileprivate let futureAsyncCancelHandler:__cswiftslash_future_result_cncl_handler_f = { ctxPtr in
	let boundPtr = ctxPtr!.assumingMemoryBound(to:AsyncResult.self)
	boundPtr.pointee.setCancel()
	boundPtr.deinitialize(count:1)
	boundPtr.deallocate()
}