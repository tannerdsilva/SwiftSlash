/*
LICENSE MIT
copyright (c) tanner silva 2026. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Synchronization
import class Dispatch.DispatchSemaphore

/// used to block a waiter for synchronous blocking until the latch is released.
/// NOTE: each instance of this class must handle a single waiter block latch. the instance is not reusable and there cannot be multiple waiters.
public final class OneShotLatch<Shot:Sendable>:Sendable {
	/// thrown when a latch is attempted to be unlocked or waited more than once - violating the one-shot semantics of this latch.
	public struct OneShotSemanticViolation:Swift.Error {}
	internal struct Core:~Copyable {
		internal private(set) var hasBeenUnlocked:Bool = false
		internal private(set) var hasBeenWaited:Bool = false
		private let semaphore:DispatchSemaphore = DispatchSemaphore(value:0)
		internal let result:Mutex<Shot?>
		fileprivate init() {
			result = .init(nil)
		}

		internal mutating func fire(_ element:sending Shot) throws(OneShotSemanticViolation) {
			guard hasBeenUnlocked == false else {
				throw OneShotSemanticViolation()
			}
			hasBeenUnlocked = true
			result.withLock { result in
				result = element
			}
			semaphore.signal()
		}

		internal mutating func semaphoreForWaiting() throws(OneShotSemanticViolation) -> DispatchSemaphore {
			guard hasBeenWaited == false else {
				throw OneShotSemanticViolation()
			}
			hasBeenWaited = true
			return semaphore
		}

		internal borrowing func resultAfterWaiting() -> Shot {
			return result.withLock { result in
				return result!
			}
		}
	}
	internal let core:Mutex<Core> = .init(.init())
	public init() {}
	public borrowing func fire(_ element:sending Shot) throws(OneShotSemanticViolation) {
		try core.withLock { coreState throws(OneShotSemanticViolation) in
			try coreState.fire(element)
		 }
	}

	private enum ShotOrSemaphore {
		case shot(Shot)
		case semaphore(DispatchSemaphore)
	}

	@available(*, noasync, message:"OneShotLatch.wait() is a synchronous blocking call. it is not compatible with async contexts.")
	public borrowing func wait() throws(OneShotSemanticViolation) -> Shot {
		let checkState:ShotOrSemaphore = try core.withLock({ coreState throws(OneShotSemanticViolation) -> ShotOrSemaphore in
			guard coreState.hasBeenUnlocked == false else {
				return coreState.result.withLock { result in
					.shot(result!)
				}
			}
			return .semaphore(try coreState.semaphoreForWaiting())
		})
		switch checkState {
			case .shot(let shot):
				return shot
			case .semaphore(let semaphore):
				semaphore.wait()
				return core.withLock { coreState in
					return coreState.resultAfterWaiting()
				}
		}
	}
}
