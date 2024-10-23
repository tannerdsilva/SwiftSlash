import __cswiftslash_future
import SwiftSlashContained

/// a reference type that represents a result that will be available in the future.
public final class Future<R>:@unchecked Sendable {

	// the deallocator function type for a successful result.
	public typealias SuccessfulResultDeallocator = (R) -> Void
	
	/// thrown when a result is set on a future that is already set.
	public struct InvalidStateError:Swift.Error {}

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
	public borrowing func setSuccess(_ result:consuming R) throws {
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
	public borrowing func setFailure(_ error:consuming Swift.Error) throws {
		let op = Unmanaged.passRetained(Contained(error)).toOpaque()
		guard __cswiftslash_future_t_broadcast_res_throw(prim, 1, op) else {
			_ = Unmanaged<Contained<Swift.Error>>.fromOpaque(op).takeRetainedValue()
			throw InvalidStateError()
		}
	}

	/// assign a function to be called when the result of the future is known. this function may be fired immediately on the current thread or on a different thread at a later time. 
	public borrowing func whenResult(_ callback:@escaping (Result<R, Swift.Error>) -> Void) {
		let arPtr = UnsafeMutablePointer<AsyncResult>.allocate(capacity:1)
		arPtr.initialize(to:AsyncResult(handler: { [cb = callback] res in
			switch res {
				case .success(let res):
					cb(.success(Unmanaged<Contained<R>>.fromOpaque(res.1!).takeUnretainedValue().value()))
				case .failure(let err):
					cb(.failure(Unmanaged<Contained<Swift.Error>>.fromOpaque(err.1!).takeUnretainedValue().value()))
				case .cancel:
					fatalError("swiftslash - cancellation on c primitive not utilized - \(#file):\(#line)")
			}
		}))
		__cswiftslash_future_t_wait_async(prim, arPtr, futureAsyncResultHandler, futureAsyncErrorHandler, futureAsyncCancelHandler)
	}
	
	/// asyncronously wait for the result of the future.
	/// - returns: the return value of the future.
	/// - throws: any error that was assigned to the future in place of a valid return instance.
	public borrowing func get() async throws -> R {
		return try await result().get()
	}

	/// asyncronously wait for the result of the future.
	/// - returns: the result of the future.
	public borrowing func result() async -> Result<R, Swift.Error> {
		return await withUnsafeContinuation({ (cont:UnsafeContinuation<Result<R, Swift.Error>, Never>) in
			var getResult = SyncResult()
			withUnsafeMutablePointer(to:&getResult) { rptr in
				__cswiftslash_future_t_wait_sync(prim, rptr, futureSyncResultHandler, futureSyncErrorHandler, futureSyncCancelHandler)
			}
			switch getResult.getResult() {
				case .success(let res):
					cont.resume(returning:.success(Unmanaged<Contained<R>>.fromOpaque(res.1!).takeUnretainedValue().value()))
				case .failure(let err):
					cont.resume(returning:.failure(Unmanaged<Contained<Swift.Error>>.fromOpaque(err.1!).takeUnretainedValue().value()))
				case .cancel:
					fatalError("swiftslash - cancellation on c primitive not utilized - \(#file):\(#line)")
			}
		})
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
				_ = Unmanaged<Contained<Swift.Error>>.fromOpaque(ptr!).takeRetainedValue()
	
		}
	}
}

fileprivate enum SuccessFailureCancel<S, F> {
	case success(S)
	case failure(F)
	case cancel // this is considered a fatal internal error and should not be developed beyond this point.
}

/// a tool to help claim the result (or error) pointers that are stored in the future at deallocation time.
fileprivate struct DeallocateTool:~Copyable {
	/// used to convey the state that was returned from the deallocation function. there may be 
	fileprivate enum State {
		case success(UInt8, UnsafeMutableRawPointer?)
		case failure(UInt8, UnsafeMutableRawPointer?)
	}
	var extractedState:State? = nil
	fileprivate init() {}
	fileprivate mutating func setResult(type:UInt8, pointer:UnsafeMutableRawPointer?) {
		extractedState = .success(type, pointer)
	}
	fileprivate mutating func setError(type:UInt8, pointer:UnsafeMutableRawPointer?) {
		extractedState = .failure(type, pointer)
	}
	fileprivate consuming func extractState() -> State {
		return extractedState!
	}
}

/// a reference type that is used to bridge the c future result handlers to strict swift types. c functions cannot be declared or utilized within the context of generic types, so types like this are used to help bridge the C functions into strict Swift typing.
fileprivate final class AsyncResult:@unchecked Sendable {
	fileprivate typealias ResultHandler = (SuccessFailureCancel<(UInt8, UnsafeMutableRawPointer?), (UInt8, UnsafeMutableRawPointer?)>) -> Void
	private let handler:UnsafeMutablePointer<ResultHandler?>
	fileprivate init(handler h:@escaping (SuccessFailureCancel<(UInt8, UnsafeMutableRawPointer?), (UInt8, UnsafeMutableRawPointer?)>) -> Void) {
		handler = UnsafeMutablePointer<ResultHandler?>.allocate(capacity:1)
		handler.initialize(to:h)
	}
	fileprivate func setResult(type:UInt8, pointer:UnsafeMutableRawPointer?) {
		handler.pointee!(.success((type, pointer)))
		handler.pointee = nil
	}
	fileprivate func setError(type:UInt8, pointer:UnsafeMutableRawPointer?) {
		handler.pointee!(.failure((type, pointer)))
		handler.pointee = nil
	}
	fileprivate func setCancel() {
		handler.pointee!(.cancel)
		handler.pointee = nil
	}
	deinit {
		handler.deinitialize(count:1)
		handler.deallocate()
	}
}

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

fileprivate let futureResultDeallocator:__cswiftslash_future_result_val_handler_f = { resType, resPtr, ctxPtr in
	ctxPtr!.assumingMemoryBound(to:DeallocateTool.self).pointee.setResult(type:resType, pointer:resPtr)
}

fileprivate let futureErrorDeallocator:__cswiftslash_future_result_err_handler_f = { errType, errPtr, ctxPtr in
	ctxPtr!.assumingMemoryBound(to:DeallocateTool.self).pointee.setError(type:errType, pointer:errPtr)
}

fileprivate let futureSyncResultHandler:__cswiftslash_future_result_val_handler_f = { resType, resPtr, ctxPtr in
	ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setResult(type:resType, pointer:resPtr)
}
fileprivate let futureSyncErrorHandler:__cswiftslash_future_result_err_handler_f = { errType, errPtr, ctxPtr in
	ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setError(type:errType, pointer:errPtr)
}
fileprivate let futureSyncCancelHandler:__cswiftslash_future_result_cncl_handler_f = { ctxPtr in
	ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setCancel()
}

fileprivate let futureAsyncResultHandler:__cswiftslash_future_result_val_handler_f = { resType, resPtr, ctxPtr in
	let boundPtr = ctxPtr!.assumingMemoryBound(to:AsyncResult.self)
	boundPtr.pointee.setResult(type:resType, pointer:resPtr)
	boundPtr.deinitialize(count:1)
	boundPtr.deallocate()
}
fileprivate let futureAsyncErrorHandler:__cswiftslash_future_result_err_handler_f = { errType, errPtr, ctxPtr in
	let boundPtr = ctxPtr!.assumingMemoryBound(to:AsyncResult.self)
	boundPtr.pointee.setError(type:errType, pointer:errPtr)
	boundPtr.deinitialize(count:1)
	boundPtr.deallocate()
}
fileprivate let futureAsyncCancelHandler:__cswiftslash_future_result_cncl_handler_f = { ctxPtr in
	let boundPtr = ctxPtr!.assumingMemoryBound(to:AsyncResult.self)
	boundPtr.pointee.setCancel()
	boundPtr.deinitialize(count:1)
	boundPtr.deallocate()
}