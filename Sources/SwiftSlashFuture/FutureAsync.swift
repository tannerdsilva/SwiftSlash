import __cswiftslash_future
import Synchronization
import SwiftSlashContained

/// a reference type that is used to bridge the c future result handlers to strict swift types. c functions cannot be declared or utilized within the context of generic types, so types like this are used to help bridge the C functions into strict Swift typing.
/// - NOTE: this type is designed with the HARD REQUIREMENT that with each initialization, a corresponding result must be set into each instance before complete dereferencing.
internal final class AsyncResult:@unchecked Sendable {
	internal typealias UniHandler = @Sendable (SuccessFailureCancel, UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?

	private struct Memory:~Copyable {
		// used as a guard to ensure that the result is only set once.
		internal let hasResult:Atomic<Bool> = .init(false)
		// the unihandler returns a pointer that later retrieved. this lock guards the reading and writing of that returned pointer.
		internal var uniHandlerReturnValueLock:pthread_mutex_t = pthread_mutex_t()
		// this lock is used to block a single waiter until the intevitable result is set.
		internal var resultWaiterLock:pthread_mutex_t = pthread_mutex_t()
		// the pointer that is returned from the unihandler. this is the pointer that is returned to the caller.
		internal let userStoragePointer:Atomic<UnsafeMutableRawPointer?>

		internal var unihandler:UniHandler?

		internal init(_ usrPtr:UnsafeMutableRawPointer?, _ handler:@escaping UniHandler) {
			pthread_mutex_init(&uniHandlerReturnValueLock, nil)
			pthread_mutex_init(&resultWaiterLock, nil)
			// there is no result yet so anyone coming in looking for a result needs to block immediately.
			// this AsyncResult is designed with the HARD REQUIREMENT that with each initialization, a corresponding result must be set into each instance before complete dereferencing. as such, we can trust that this lock will be balanced at result time.
			pthread_mutex_lock(&resultWaiterLock)
			unihandler = handler
			userStoragePointer = .init(usrPtr)
		}
		internal mutating func fireUniHandler(_ result:SuccessFailureCancel) -> UnsafeMutableRawPointer? {
			defer {
				unihandler = nil
			}
			return unihandler!(result, userStoragePointer.load(ordering:.acquiring))
		}
		internal func tryAssignResult() -> Bool {
			return hasResult.compareExchange(expected:false, desired:true, successOrdering:.acquiringAndReleasing, failureOrdering:.relaxed).exchanged
		}
		internal mutating func lockUHReturnValueLock() {
			pthread_mutex_lock(&uniHandlerReturnValueLock)
		}
		internal mutating func unlockUHReturnValueLock() {
			pthread_mutex_unlock(&uniHandlerReturnValueLock)
		}
		internal mutating func storeUHReturnValue(_ pointer:UnsafeMutableRawPointer?) {
			userStoragePointer.store(pointer, ordering:.releasing)
			pthread_mutex_unlock(&resultWaiterLock)
		}
		internal mutating func waitForResult() -> UnsafeMutableRawPointer? {
			pthread_mutex_lock(&resultWaiterLock)
			pthread_mutex_lock(&uniHandlerReturnValueLock)
			pthread_mutex_unlock(&resultWaiterLock)
			let rv = userStoragePointer.load(ordering:.acquiring)
			pthread_mutex_unlock(&uniHandlerReturnValueLock)
			return rv
		}
		deinit {
			guard hasResult.load(ordering:.acquiring) == true else {
				fatalError("invalid state for future result setting. \(#file):\(#line)")
			}

			var mutex = uniHandlerReturnValueLock
			pthread_mutex_destroy(&mutex)
			mutex = resultWaiterLock
			pthread_mutex_destroy(&mutex)
		}
	}

	private let workingMemory:UnsafeMutablePointer<Memory> = .allocate(capacity:1)

	internal init(ptr:UnsafeMutableRawPointer?, handle:consuming @escaping UniHandler) {
		workingMemory.initialize(to:.init(ptr, handle))
	}

	internal borrowing func setResult(type:consuming UInt8, pointer:consuming UnsafeMutableRawPointer?) {
		guard workingMemory.pointee.tryAssignResult() == true else {
			fatalError("invalid state for future result setting. \(#file):\(#line)")
		}
		workingMemory.pointee.lockUHReturnValueLock()
		let p = workingMemory.pointee.fireUniHandler(.success(type, pointer))
		workingMemory.pointee.storeUHReturnValue(p)
		workingMemory.pointee.unlockUHReturnValueLock()
	}
	internal borrowing func setError(type:consuming UInt8, pointer:consuming UnsafeMutableRawPointer?) {
		guard workingMemory.pointee.tryAssignResult() == true else {
			fatalError("invalid state for future result setting. \(#file):\(#line)")
		}
		workingMemory.pointee.lockUHReturnValueLock()
		let p = workingMemory.pointee.fireUniHandler(.failure(type, pointer))
		workingMemory.pointee.storeUHReturnValue(p)
		workingMemory.pointee.unlockUHReturnValueLock()
	}
	internal borrowing func setCancel() {
		guard workingMemory.pointee.tryAssignResult() == true else {
			fatalError("invalid state for future result setting. \(#file):\(#line)")
		}
		workingMemory.pointee.lockUHReturnValueLock()
		let p = workingMemory.pointee.fireUniHandler(.cancel)
		workingMemory.pointee.storeUHReturnValue(p)
		workingMemory.pointee.unlockUHReturnValueLock()
	}
	internal borrowing func wait() -> UnsafeMutableRawPointer? {
		return workingMemory.pointee.waitForResult()
	}

	deinit {
		guard workingMemory.pointee.hasResult.load(ordering:.acquiring) == true else {
			fatalError("invalid state for future result setting. \(#file):\(#line)")
		}

		workingMemory.deinitialize(count:1)
		workingMemory.deallocate()
	}
}