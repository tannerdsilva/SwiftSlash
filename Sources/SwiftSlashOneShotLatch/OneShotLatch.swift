/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Synchronization
import class Dispatch.DispatchSemaphore

/// used to block a waiter for synchronous waiting.
/// NOTE: this class is marked with `unchecked Sendable` because it is assumed that this tool will only be used within the "state mutex" of the future.
/// NOTE: each instance of this class must handle a single waiter block latch. the instance is not reusable and there cannot be multiple waiters.
public final class OneShotLatch:Sendable {
	/// thrown when a latch is attempted to be unlocked or waited more than once - violating the one-shot semantics of this latch.
	public struct OneShotSemanticViolation:Swift.Error {}
	internal struct Core:~Copyable {
		private let hasBeenUnlocked:Atomic<Bool> = .init(false)
		private let hasBeenWaited:Atomic<Bool> = .init(false)
		private let semaphore:DispatchSemaphore
		fileprivate init() {
			semaphore = DispatchSemaphore(value:0)
		}

		internal borrowing func unlock() throws(OneShotSemanticViolation) {
			guard hasBeenUnlocked.compareExchange(expected:false, desired: true, successOrdering:.acquiringAndReleasing, failureOrdering:.relaxed).exchanged == false else {
				throw OneShotSemanticViolation()
			}
			semaphore.signal()
		}

		internal borrowing func wait() throws(OneShotSemanticViolation) {
			guard hasBeenWaited.compareExchange(expected:false, desired: true, successOrdering:.acquiringAndReleasing, failureOrdering:.relaxed).exchanged == false else {
				throw OneShotSemanticViolation()
			}
			semaphore.wait()
		}
	}
	internal let core:Core = .init()
	public init() {}
	public borrowing func unlock() throws(OneShotSemanticViolation) {
		try core.unlock()
	}
	public borrowing func wait() throws(OneShotSemanticViolation) {
		try core.wait()
	}
}
