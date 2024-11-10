import __cswiftslash_future
import __cswiftslash_auint8

/// a reference type that is used to bridge the c future result handlers to strict swift types. c functions cannot be declared or utilized within the context of generic types, so types like this are used to help bridge the C functions into strict Swift typing.
internal final class AsyncResult:@unchecked Sendable {
	internal typealias UniHandler = (SuccessFailureCancel, UnsafeMutableRawPointer?) -> Void

	private let memorySpace:UnsafeMutablePointer<(pthread_mutex_t, pthread_mutex_t, __cswiftslash_atomic_uint8_t, UniHandler?)>
	private let storage:UnsafeMutableRawPointer?

	private let internalStateMutex:UnsafeMutablePointer<pthread_mutex_t>
	
	private let resultMutex:UnsafeMutablePointer<pthread_mutex_t>
	private let isResultMutexLocked:UnsafeMutablePointer<__cswiftslash_atomic_uint8_t>

	private let uniHandler:UnsafeMutablePointer<UniHandler?>

	internal init(storage strPtr:UnsafeMutableRawPointer?, handle:consuming @escaping UniHandler) {
		memorySpace = UnsafeMutablePointer<(pthread_mutex_t, pthread_mutex_t, __cswiftslash_atomic_uint8_t, UniHandler?)>.allocate(capacity:1)
		memorySpace.initialize(to:(pthread_mutex_t(), pthread_mutex_t(), __cswiftslash_auint8_init(1), handle))
		pthread_mutex_init(&memorySpace.pointee.0, nil)
		pthread_mutex_init(&memorySpace.pointee.1, nil)
		pthread_mutex_lock(&memorySpace.pointee.1)
		storage = strPtr
		internalStateMutex = memorySpace.pointer(to:\.0)!
		resultMutex = memorySpace.pointer(to:\.1)!
		isResultMutexLocked = memorySpace.pointer(to:\.2)!
		uniHandler = memorySpace.pointer(to:\.3)!
	}
	internal borrowing func setResult(type:consuming UInt8, pointer:consuming UnsafeMutableRawPointer?) {
		pthread_mutex_lock(internalStateMutex)
		defer {
			pthread_mutex_unlock(internalStateMutex)
		}

		var expected:UInt8 = 1
		if __cswiftslash_auint8_compare_exchange_weak(isResultMutexLocked, &expected, 0) {
			pthread_mutex_unlock(resultMutex)
			uniHandler.pointee!(.success(type, pointer), storage)
			uniHandler.pointee = nil
		}
	}
	internal borrowing func setError(type:consuming UInt8, pointer:consuming UnsafeMutableRawPointer?) {
		pthread_mutex_lock(internalStateMutex)
		defer {
			pthread_mutex_unlock(internalStateMutex)
		}

		var expected:UInt8 = 1
		if __cswiftslash_auint8_compare_exchange_weak(isResultMutexLocked, &expected, 0) {
			pthread_mutex_unlock(resultMutex)
			uniHandler.pointee!(.failure(type, pointer), storage)
			uniHandler.pointee = nil
		}
	}
	internal borrowing func setCancel() {
		pthread_mutex_lock(internalStateMutex)
		defer {
			pthread_mutex_unlock(internalStateMutex)
		}

		var expected:UInt8 = 1
		if __cswiftslash_auint8_compare_exchange_weak(isResultMutexLocked, &expected, 0) {
			pthread_mutex_unlock(resultMutex)
			uniHandler.pointee!(.cancel, storage)
			uniHandler.pointee = nil
		}
	}
	internal borrowing func wait<T>(loadingAs:T.Type) async -> T {
		return await withUnsafeContinuation({ (continuation:UnsafeContinuation<T, Never>) in
			pthread_mutex_lock(resultMutex)
			pthread_mutex_lock(internalStateMutex)
			pthread_mutex_unlock(resultMutex)
			continuation.resume(returning:storage!.assumingMemoryBound(to:T.self).pointee)
			pthread_mutex_unlock(internalStateMutex)
		})
	}
	internal borrowing func wait(loadingAs:Void.Type = Void.self) async {
		await withUnsafeContinuation({ (continuation:UnsafeContinuation<Void, Never>) in
			pthread_mutex_lock(resultMutex)
			pthread_mutex_lock(internalStateMutex)
			pthread_mutex_unlock(resultMutex)
			pthread_mutex_unlock(internalStateMutex)
			continuation.resume()
		})
	}

	deinit {
		
		// destroy and deallocate internal state mutex
		pthread_mutex_destroy(internalStateMutex)

		// unlock the result mutex if it is still locked
		if __cswiftslash_auint8_load(isResultMutexLocked) == 1 {
			pthread_mutex_unlock(resultMutex)
		}

		// destroy and deallocate the result mutex
		pthread_mutex_destroy(resultMutex)

		// deallocate the unified memory space for the async result
		memorySpace.deinitialize(count:1)
		memorySpace.deallocate()
	}
}