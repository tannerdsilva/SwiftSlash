/* LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Synchronization
import SwiftSlashOneShotLatch

/// fifo is a mechanism that operates very similarly to a native Swift AsyncStream. the tool is designed for use with a single producer and a single consumer. the tool is thread-safe and reentrancy-safe, but is *not* intended for use with multiple producers or multiple consumers.
/// ### the semantics of the FIFO are as follows:
/// - the FIFO is initialized with an optional maximum buffered element count. if there is always a 'waiter' ready to consume the next element, then the FIFO will not buffer any elements. if there is no 'waiter' ready to consume the next element, then the FIFO will buffer elements up to the maximum buffered element count. if the maximum buffered element count is reached, then any further attempts to yield an element into the FIFO will fail with a BufferLimitExceeded error.
/// - with the buffer limits always being met, the FIFO will pass any 'n' umber of elements from the producer to the consumer.
/// - the FIFO can be "capped" or "finished" with one of two possible results: a success result, or a failure result.
/// - a FIFO may be finished with elements still buffered in the FIFO. in this case, the FIFO will continue to pass elements to the consumer until the buffer is empty, at which point the FIFO will return the result of the finish operation (success or failure) to the consumer.
/// - if the maximum buffered count is NOT `nil`, the value must be greater than 0.
public final class FIFOv2<Element:Sendable, Failure:Swift.Error>:Sendable {

	/// the type of the next element that will be yielded from the FIFO. this type is used to convey the result of the next() operation, which may be a successful element, a failure, or nil if the FIFO has been closed.
	public typealias NextElement = Result<Element, Failure>?

	/// thrown when there is already a waiter for the fifo.
	public struct AlreadyWaiting:Swift.Error {}

	/// thrown when the fifo is in an invalid state for the operation being attempted.
	public struct InvalidStateError:Swift.Error {}

	/// thrown when an invalid maximum element count is specified for the fifo. the maximum element count must be greater than 0, or nil for an unbounded fifo.
	public struct InvalidMaximumElementCount:Swift.Error {}

	/// used to specify what should happen when the consuming task of this fifo is cancelled.
	public enum WhenConsumingTaskCancelled:Sendable {
		/// take no action. the fifo will continue passing objects as it normally does.
		case noAction
		/// finish the fifo with a specified result. this will cause the fifo to stop yielding new objects, and will cause any future calls to next() to return the specified result (after the buffer has been cleared).
		case finish(Result<Void, Failure>)
	}

	/// a mechanism that is used to synchronously block a thread until the next element is available in the FIFO. this mechanism is used to allow synchronous code to wait for the next element in the FIFO without using async/await.
	public struct SyncWaiter:Sendable {
		/// the oneshot latch that is used to block the thread until the next element is available in the FIFO.
		internal let oneShot:OneShotLatch<NextElement>
		/// initialize the SyncWaiter with a OneShotLatch instance.
		internal init(_ oneShotIn:OneShotLatch<NextElement>) {
			oneShot = oneShotIn
		}
		/// waits for the next element to be available in the FIFO. this function will block the current thread until the next element is available, or until the FIFO is closed.
		/// - returns: the next element in the FIFO, or nil if the FIFO has been closed without an error.
		public func wait() -> NextElement {
			// any breakage in the "one shot semantics" of the OneShotLatch is a programming error, so we will force-try this operation. if it fails, it is a programming error and we want to crash.
			return try! oneShot.wait()
		}
	}

	/// used to convey one of the possible outcomes of consuming the next element from the FIFO.
	public enum ConsumeResult {
		/// the next element was successfully consumed from the FIFO.
		case element(Element)
		/// the FIFO was closed, and no more elements may be consumed.
		case capped(Result<Void, Failure>)
		/// the FIFO is currently empty, and no elements may be consumed at this time.
		case wouldBlock(SyncWaiter)
	}

	/// used to convey the various types of results that may occur when yielding an element into the FIFO.
	public enum YieldResult {
		/// the yield value was successfully passed into the FIFO
		case success
		/// the FIFO was closed, and the yield value was not passed into the FIFO
		case fifoClosed
		/// the FIFO was full, and the yield value was not passed into the FIFO
		case fifoFull
	}

	/// internal struct to convey the result of a yield operation, and any waiter notification that may be required.
	private struct YieldOutcome {
		/// the result of the yield operation.
		internal let result:YieldResult
		/// any waiter notification that may be required as a result of the yield operation. if this value is nil, then there is no waiter to notify.
		internal let waiterNotification:Core.State.Unfinished.YieldResult?
		internal init(result resultIn:YieldResult, waiterNotification waiterNotificationIn:Core.State.Unfinished.YieldResult?) {
			result = resultIn
			waiterNotification = waiterNotificationIn
		}
	}

	/// the number of elements that are being buffered in the FIFO. this value is updated atomically, and may be read from any thread.
	private let count:Atomic<UInt64> = Atomic(0)
	/// the core state of the FIFO.
	private let core:Mutex<Core.State>

	/// initialize the FIFO with an optional maximum element count.
	/// - parameter maxElements: the maximum number of elements that may be buffered in the FIFO. if this value is nil, the FIFO will be unbounded.
	/// - throws: InvalidMaximumElementCount if the maxElements parameter is 0.
	internal init(maxElementsBuffered maxElements:UInt64?) throws(InvalidMaximumElementCount) {
		core = Mutex(try .init(maxElementsBuffered: maxElements))
	}

	/// yields an element into the FIFO.
	/// - parameter element: the element to yield into the FIFO.
	/// - returns: a YieldResult value indicating the result of the yield operation.
	internal func yield(_ element:sending Element) -> YieldResult {
		// enter the locked section of the fifo core state, and attempt to yield the element into the FIFO. return the result of the yield operation.
		let lockResult = core.withLock { state -> YieldOutcome in
			// check if the fifo has already been finished.
			switch state.capResult {
				case .some(_):
					// the fifo has already been finished, so we cannot yield any more elements.
					return YieldOutcome(result: .fifoClosed, waiterNotification: nil)
				case .none:
					// the fifo is still open, so we can attempt to yield the element.
					return withUnsafePointer(to: count) { countPtr in
						do {
							return YieldOutcome(result: .success, waiterNotification: try state.unfinished.yield(elementCount:countPtr, element))
						} catch {
							return YieldOutcome(result: .fifoFull, waiterNotification: nil)
						}
					}
			}
		}
		switch lockResult.waiterNotification {
			case .some(let yieldOutcome):
				switch yieldOutcome {
					case .buffered:
						// the element was buffered in the FIFO, and there was no pending waiter to notify.
						break
					case .waiterNotificationRequired(let waiterInfo, let result):
						// there is a waiter, so we need to notify them that an element is now available.
						switch waiterInfo {
							case .synchronous(let oneShot):
								// this is a synchronous waiter, so we will fire the one-shot latch with the result of the fifo.
								// any breakage in the "one shot semantics" of the OneShotLatch is a programming error, so we will force-try this operation. if it fails, it is a programming error and we want to crash.
								try! oneShot.fire(result)
							case .asynchronous(let continuation):
								// handle the asynchronous waiter
								continuation.resume(returning:.success(result))
						}
				}
			case .none:
				// there is no waiter, so we do not need to do anything.
				break;
		}

		// return the result of the yield operation.
		return lockResult.result	
	}

	private func finish(cappingWith result:Result<Void, Failure>) throws(InvalidStateError) {
		switch try core.withLock({ (state) throws(InvalidStateError) -> Core.State.Unfinished.WaiterInfo? in
			// if the fifo has already been finished, we do not need to do anything.
			switch state.capResult {
				case .some(_):
					throw InvalidStateError()
				case .none:
					state.capResult = result
			}
			defer {
				state.unfinished.waiter = nil
			}
			// check for a waiter.
			return state.unfinished.waiter
		}) {
			// there is already a waiter, so we need to notify them that the fifo has been finished.
			case .some(let waiter):
				switch waiter {
					// this is a synchronous waiter, so we will fire the one-shot latch with the result of the fifo.
					case .synchronous(let oneShot):
						switch result {
							case .success:
								// any breakage in the "one shot semantics" of the OneShotLatch is a programming error, so we will force-try this operation. if it fails, it is a programming error and we want to crash.
								try! oneShot.fire(nil)
							case .failure(let error):
								// any breakage in the "one shot semantics" of the OneShotLatch is a programming error, so we will force-try this operation. if it fails, it is a programming error and we want to crash.
								try! oneShot.fire(.failure(error))
						}
					case .asynchronous(let continuation):
						// handle the asynchronous waiter
						switch result {
							case .success:
								// resume the continuation with a nil value, indicating that the fifo has been finished successfully.
								continuation.resume(returning:.success(nil))
							case .failure(let error):
								// resume the continuation with a failure value, indicating that the fifo has been finished with an error.
								continuation.resume(returning:.success(.failure(error)))
						}
				}
			case .none:
				// there is no waiter, so we do not need to do anything.
				break
		}
	}

	/// finishes the FIFO with a success result. this will cause the FIFO to stop passing objects and return nil for any future calls to next() (after the buffer has been cleared).
	/// - throws: InvalidStateError if the FIFO has already been finished.
	internal func finish() throws(InvalidStateError) {
		try finish(cappingWith:.success(()))
	}

	/// finishes the FIFO with a failure result. this will cause the FIFO to stop passing objects and throw this error for any future calls to next() (after the buffer has been cleared).
	/// - parameter error: the error to finish the FIFO with.
	/// - throws: InvalidStateError if the FIFO has already been finished.
	internal func finish(withError error:consuming Failure) throws(InvalidStateError) {
		try finish(cappingWith:.failure(error))
	}
}

extension FIFOv2 {
	internal func next(onCurrentTaskCancelled action:WhenConsumingTaskCancelled) async throws(AlreadyWaiting) -> NextElement {
		return try await withTaskCancellationHandler(operation: {
			return await nextAsynchronous()
		}, onCancel: { [weak self] in
			guard let self = self else {
				return
			}
			switch action {
				case .noAction:
					break
				case .finish(let result):
					try? self.finish(cappingWith:result)
			}
		}).get()
	}
	internal func nextAsynchronous() async -> Result<NextElement, AlreadyWaiting> {
		return await withUnsafeContinuation({ (continuation:UnsafeContinuation<Result<NextElement, AlreadyWaiting>, Never>) in
			let hasImmediateResult:Result<NextElement, AlreadyWaiting>? = core.withLock({ state in
				withUnsafePointer(to:count, { countPtr in
					// validate that there is not already a waiter.
					guard state.unfinished.waiter == nil else {
						return .failure(AlreadyWaiting())
					}

					// validate that there is no elements available in the buffer.
					let acquireNext = state.unfinished.consumeNext(elementCount:countPtr)
					guard acquireNext == nil else {
						// there is an element available, so we will return it immediately.
						return .success(.success(acquireNext!))
					}

					// check if the fifo has been finished.
					switch state.capResult {
						case .some(let capResult):
							// the fifo has been finished, so we will return the cap result immediately.
							switch capResult {
								case .success:
									return .success(nil)
								case .failure(let error):
									return .success(.failure(error))
							}
						case .none:
							// there is no element available, and the fifo has not been finished, so we will set the waiter to the continuation.
							// note that this is the only place where nil is returned, hence, the only place where the continuation is not handled immediately. as such, the continuation will be resumed when an element is yielded into the fifo, or when the fifo is finished.
							state.unfinished.waiter = .asynchronous(continuation)
							return nil
					}
				})
			})
			if hasImmediateResult != nil {
				continuation.resume(returning:hasImmediateResult!)
			}
		})
	}

	internal func nextSynchronous() throws(AlreadyWaiting) -> ConsumeResult {
		return try core.withLock({ state throws(AlreadyWaiting) in
			return try withUnsafePointer(to:count, { countPtr throws(AlreadyWaiting) -> ConsumeResult in
				// validate that there is not already a waiter.
				guard state.unfinished.waiter == nil else {
					throw AlreadyWaiting()
				}

				// validate that there is no elements available.
				let acquireNext = state.unfinished.consumeNext(elementCount:countPtr)
				guard acquireNext == nil else {
					// there is an element available, so we will return it immediately.
					return .element(acquireNext!)
				}
				
				// check if the fifo has been finished.
				switch state.capResult {
					case .some(let capResult):
						// the fifo has been finished, so we will return the cap result immediately.
						switch capResult {
							case .success:
								return .capped(.success(()))
							case .failure(let error):
								return .capped(.failure(error))
						}
					case .none:
						// the fifo has not been finished. wrap the latch in a waiter and return it to the caller, so that they can wait for the next element to be available.
						let newLatch = OneShotLatch<NextElement>()
						state.unfinished.waiter = .synchronous(newLatch)
						return .wouldBlock(SyncWaiter(newLatch))
				}
			})
		})
	}
}