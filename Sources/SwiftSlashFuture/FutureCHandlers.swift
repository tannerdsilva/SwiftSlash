import __cswiftslash_future

internal enum SuccessFailureCancel {
	case success(UInt8, UnsafeMutableRawPointer?)
	case failure(UInt8, UnsafeMutableRawPointer?)
	case cancel
}

/// the sync handler for results
internal let futureSyncResultHandler:__cswiftslash_future_result_val_handler_f = { resType, resPtr, ctxPtr in
	ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setResult(type:resType, pointer:resPtr)
}
/// the sync handler for errors
internal let futureSyncErrorHandler:__cswiftslash_future_result_err_handler_f = { errType, errPtr, ctxPtr in
	ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setError(type:errType, pointer:errPtr)
}
/// the sync handler for cancellations
internal let futureSyncCancelHandler:__cswiftslash_future_result_cncl_handler_f = { ctxPtr in
	ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setCancel()
}

/// the async handler for results
internal let futureAsyncResultHandler:__cswiftslash_future_result_val_handler_f = { resType, resPtr, ctxPtr in
	let boundPtr = ctxPtr!.assumingMemoryBound(to:AsyncResult.self)
	boundPtr.pointee.setResult(type:resType, pointer:resPtr)
	boundPtr.deinitialize(count:1)
	boundPtr.deallocate()
}
/// the async handler for errors
internal let futureAsyncErrorHandler:__cswiftslash_future_result_err_handler_f = { errType, errPtr, ctxPtr in
	let boundPtr = ctxPtr!.assumingMemoryBound(to:AsyncResult.self)
	boundPtr.pointee.setError(type:errType, pointer:errPtr)
	boundPtr.deinitialize(count:1)
	boundPtr.deallocate()
}
/// the async handler for cancellations
internal let futureAsyncCancelHandler:__cswiftslash_future_result_cncl_handler_f = { ctxPtr in
	let boundPtr = ctxPtr?.assumingMemoryBound(to:AsyncResult.self)
	boundPtr?.pointee.setCancel()
	boundPtr?.deinitialize(count:1)
	boundPtr?.deallocate()
}