/* LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Synchronization
import SwiftSlashOneShotLatch

/// fifo is a mechanism that operates very similarly to a native Swift AsyncStream. the tool is designed for use with a single producer and a single consumer. the tool is thread-safe and reentrancy-safe, but is not intended for use with multiple producers or multiple consumers.
public final class FIFOv2<Element:Sendable, Failure:Swift.Error>:Sendable {

	/// thrown when there is already a waiter for the fifo.
	public struct AlreadyWaiting:Swift.Error {}

	/// thrown when the fifo is in an invalid state for the operation being attempted.
	public struct InvalidStateError:Swift.Error {}

	/// thrown when an invalid maximum element count is specified for the fifo. the maximum element count must be greater than 0, or nil for an unbounded fifo.
	public struct InvalidMaximumElementCount:Swift.Error {}

	/// used to specify what should happen when the consuming task of this fifo is cancelled.
	public enum WhenConsumingTaskCancelled {
		/// take no action. the fifo will continue passing objects as it normally does.
		case noAction
		/// finish the fifo with a success result. this will cause the fifo to stop passing objects and return nil for any future calls to next() (after the buffer has been cleared).
		case finish
	}

	/// used to convey one of the possible outcomes of consuming the next element from the FIFO.
	public enum ConsumeResult {
		/// the next element was successfully consumed from the FIFO.
		case element(Element)
		/// the FIFO was closed, and no more elements may be consumed.
		case capped(Result<Void, Failure>)
		/// the FIFO is currently empty, and no elements may be consumed at this time.
		case wouldBlock
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
		return core.withLock { state in
			// check if the fifo has already been finished.
			switch state.capResult {
				case .some(_):
					// the fifo has already been finished, so we cannot yield any more elements.
					return .fifoClosed
				case .none:
					// the fifo is still open, so we can attempt to yield the element.
					return withUnsafePointer(to: count) { countPtr in
						do {
							try state.unfinished.yield(elementCount:countPtr, element)
							return .success
						} catch {
							return .fifoFull
						}
					}
			}
		}
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
								try! oneShot.fire(nil)
							case .failure(let error):
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

	internal func finish() throws(InvalidStateError) {
		try finish(cappingWith:.success(()))
	}

	internal func finish(withError error:Failure) throws(InvalidStateError) {
		try finish(cappingWith:.failure(error))
	}
}

extension FIFOv2 {
	internal func next() async throws(AlreadyWaiting) -> Result<Element, Failure>? {
		return try await withUnsafeContinuation({ (continuation:UnsafeContinuation<Result<Result<Element, Failure>?, AlreadyWaiting>, Never>) in
			core.withLock({ state in
				withUnsafePointer(to:count, { countPtr in
					// validate that there is not already a waiter.
					guard state.unfinished.waiter == nil else {
						continuation.resume(returning:.failure(AlreadyWaiting()))
						return
					}

					// validate that there is no elements available in the buffer.
					let acquireNext = state.unfinished.consumeNext(elementCount:countPtr)
					guard acquireNext == nil else {
						// there is an element available, so we will return it immediately.
						continuation.resume(returning:.success(.success(acquireNext!)))
						return
					}
					
					// check if the fifo has been finished.
					switch state.capResult {
						case .some(let capResult):
							// the fifo has been finished, so we will return the cap result immediately.
							switch capResult {
								case .success:
									continuation.resume(returning:.success(nil))
								case .failure(let error):
									continuation.resume(returning:.success(.failure(error)))
							}
							return
						case .none:
							// the fifo has not been finished.
							break;
					}

					// there is no element available, and the fifo has not been finished, so we will set the waiter to the continuation.
					state.unfinished.waiter = .asynchronous(continuation)
				})
			})
		}).get()
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
						// the fifo has not been finished.
						return .wouldBlock
				}
			})
		})
	}
}