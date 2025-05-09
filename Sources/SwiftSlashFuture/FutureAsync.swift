/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_future
import Synchronization
import SwiftSlashContained

/// a reference type that is used to bridge the c future result handlers to strict swift types. c functions cannot be declared or utilized within the context of generic types, so types like this are used to help bridge the C functions into strict Swift typing.
/// - NOTE: this type is designed with the HARD REQUIREMENT that with each initialization, a corresponding result must be set into each instance before complete dereferencing.
internal final class AsyncResult:@unchecked Sendable {
	internal typealias UniHandler = @Sendable (SuccessFailureCancel) -> Void
	private struct Memory:~Copyable {
		// used as a guard to ensure that the result is only set once.
		internal let hasResult:Atomic<Bool> = .init(false)
		// this lock is used to block a single waiter until the intevitable result is set.
		internal var resultWaiterLock:pthread_mutex_t = pthread_mutex_t()

		internal var unihandler:UniHandler?

		internal init(handler:@escaping UniHandler) {
			pthread_mutex_init(&resultWaiterLock, nil)
			// there is no result yet so anyone coming in looking for a result needs to block immediately.
			// this AsyncResult is designed with the HARD REQUIREMENT that with each initialization, a corresponding result must be set into each instance before complete dereferencing. as such, we can trust that this lock will be balanced at result time.
			pthread_mutex_lock(&resultWaiterLock)
			unihandler = handler
		}
		internal init() {
			pthread_mutex_init(&resultWaiterLock, nil)
			// there is no result yet so anyone coming in looking for a result needs to block immediately.
			// this AsyncResult is designed with the HARD REQUIREMENT that with each initialization, a corresponding result must be set into each instance before complete dereferencing. as such, we can trust that this lock will be balanced at result time.
			pthread_mutex_lock(&resultWaiterLock)
			unihandler = nil
		}
		internal mutating func fireUniHandler(_ result:SuccessFailureCancel) {
			if unihandler != nil {
				unihandler!(result)
				unihandler = nil
			}
			pthread_mutex_unlock(&resultWaiterLock)
		}
		internal func tryAssignResult() -> Bool {
			return hasResult.compareExchange(expected:false, desired:true, successOrdering:.acquiringAndReleasing, failureOrdering:.relaxed).exchanged
		}
		internal mutating func exclusiveWait() {
			pthread_mutex_lock(&resultWaiterLock)
		}
		deinit {
			guard hasResult.load(ordering:.acquiring) == true else {
				fatalError("invalid state for future result setting. \(#file):\(#line)")
			}
			var mutex = resultWaiterLock
			pthread_mutex_unlock(&mutex)
			pthread_mutex_destroy(&mutex)
		}
	}

	private let workingMemory:UnsafeMutablePointer<Memory> = .allocate(capacity:1)

	internal init(handle:consuming @escaping UniHandler) {
		workingMemory.initialize(to:.init(handler:handle))
	}

	internal init() {
		workingMemory.initialize(to:.init())
	}

	internal borrowing func setResult(type:consuming UInt8, pointer:consuming UnsafeMutableRawPointer?) {
		guard workingMemory.pointee.tryAssignResult() == true else {
			fatalError("invalid state for future result setting. \(#file):\(#line)")
		}
		workingMemory.pointee.fireUniHandler(.success(type, pointer))
	}
	internal borrowing func setError(type:consuming UInt8, pointer:consuming UnsafeMutableRawPointer?) {
		guard workingMemory.pointee.tryAssignResult() == true else {
			fatalError("invalid state for future result setting. \(#file):\(#line)")
		}
		workingMemory.pointee.fireUniHandler(.failure(type, pointer))
	}
	internal borrowing func setCancel() {
		guard workingMemory.pointee.tryAssignResult() == true else {
			fatalError("invalid state for future result setting. \(#file):\(#line)")
		}
		workingMemory.pointee.fireUniHandler(.cancel)
	}
	internal borrowing func exclusiveWait() {
		return workingMemory.pointee.exclusiveWait()
	}

	deinit {
		guard workingMemory.pointee.hasResult.load(ordering:.acquiring) == true else {
			fatalError("invalid state for future result setting. \(#file):\(#line)")
		}

		workingMemory.deinitialize(count:1)
		workingMemory.deallocate()
	}
}