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

	internal struct Core:~Copyable {
		/// thrown when the fifo is full and cannot accept any more elements.
		internal struct BufferLimitExceeded:Swift.Error {}

		/// the unfinished state of the FIFO. this is the state that is used to pass elements through the FIFO.
		/// - NOTE: the unfinished state does not keep track of whether or not the FIFO has been closed.
		internal struct Unfinished:~Copyable {
			
			/// used to hold a pair of references to the base and tail links of the FIFO.
			private struct ReferencePair:~Copyable {
				
				/// the link is a reference type that is used to hold an element in the FIFO. it links together with other links 
				internal final class Link {
					/// the element that is being held in the link.
					internal let element:Element
					/// a reference to the next link in the FIFO. if this value is nil, then this link is the tail of the FIFO.
					internal var next:Link? = nil
					/// initialize the link with an element.
					/// - parameter elementIn: the element to hold in the link.
					internal init(_ elementIn:consuming Element) {
						element = elementIn
					}
					/// consumes the element from the link. this function is used to remove the element from the link when it is being removed from the FIFO.
					/// - returns: the element that was held in the link.
					internal consuming func consumeElement() -> sending Element {
						return element
					}
				}

				/// the maximum element count that may be buffered in this fifo.
				internal let maxElementsBuffered:UInt64?
				/// a reference to the base link of the FIFO
				private var base:Link? = nil
				/// a reference to the tail link of the FIFO
				private var tail:Link? = nil

				/// initialize the ReferencePair with an optional maximum element count.
				/// - parameter maxElements: the maximum number of elements that may be buffered in the FIFO. if this value is nil, the FIFO will be unbounded.
				internal init(maxElementsBuffered maxElements:UInt64?) {
					maxElementsBuffered = maxElements
				}
				
				/// inserts a new link at the tail of the FIFO. this function will increment the elementCount property.
				/// - parameter link: the link to insert at the tail of the FIFO.
				internal mutating func addElement(elementCount:UnsafePointer<Atomic<UInt64>>, _ link:Element) throws(BufferLimitExceeded) {
					guard maxElementsBuffered == nil || elementCount.pointee.load(ordering:.sequentiallyConsistent) < maxElementsBuffered! else {
						throw BufferLimitExceeded()
					}
					defer {
						elementCount.pointee.add(1, ordering:.sequentiallyConsistent)
					}
					let link = Link(link)
					switch (base, tail) {
						case (nil, nil):
							// there are no existing elements in the FIFO, so we must set both the base and tail to the new link.
							base = link
							tail = link
						case (_, let t?):
							// there are existing elements in the FIFO, so we must set the next property of the tail to the new link, and then update the tail to the new link.
							t.next = link
							tail = link
						default:
							fatalError("SwiftSlashFIFO: ReferencePair is in an invalid state. \(#file):\(#line)")
					}
				}

				/// removes the link at the base of the FIFO. this function will decrement the elementCount property.
				/// - returns: the link that was removed from the base of the FIFO, or nil if the FIFO is empty.
				internal mutating func removeElement(elementCount:UnsafePointer<Atomic<UInt64>>) -> sending Element? {
					switch (base, tail) {
						case (nil, nil):
							return nil
						case (let b?, let t?):
							defer {
								elementCount.pointee.subtract(1, ordering:.sequentiallyConsistent)
							}
							if b === t {
								base = nil
								tail = nil
								b.next = nil
								return b.consumeElement()
							} else {
								base = b.next
								if base == nil {
									tail = nil
								}
								return b.consumeElement()
							}
						default:
							fatalError("SwiftSlashFIFO: ReferencePair is in an invalid state. \(#file):\(#line)")
					}
				}
			}

			/// specifies one of the two kinds of waiters that can exist 
			internal enum WaiterInfo:Sendable {
				case synchronous(OneShotLatch<Result<Element, Failure>?>)
				case asynchronous(UnsafeContinuation<Result<Result<Element, Failure>?, AlreadyWaiting>, Never>)
			}

			/// used to track whether the FIFO has been closed. if the FIFO is closed, no more elements may be yielded into the FIFO.
			private var pair:ReferencePair
			
			/// there may be a single waiter for the FIFO. if there is a waiter, it will be stored here. if there is no waiter, this value will be nil.
			/// - NOTE: a waiter must only be a non-nil value if the FIFO is empty. if the FIFO is not empty, there should be no waiter, and this value should be nil.
			internal var waiter:WaiterInfo? = nil

			internal init(maxElementsBuffered maxElements:UInt64?) {
				guard maxElements != 0 else {
					fatalError("SwiftSlashFIFO: maxElementsBuffered must be greater than 0. \(#file):\(#line). if you wish to specify an unbounded FIFO, pass nil for the maxElementsBuffered parameter.")
				}
				pair = ReferencePair(maxElementsBuffered: maxElements)
			}

			/// yields an element into the FIFO.
			/// - parameter element: the element to yield into the FIFO.
			/// - returns: a Bool value indicating whether the yield was successful. if the FIFO is full, the yield will fail and return false.
			internal mutating func yield(elementCount:UnsafePointer<Atomic<UInt64>>, _ element:sending Element) throws(BufferLimitExceeded) {
				// if there is a waiter, we must notify them that an element is now available.
				switch waiter {
					case .some(let w):
						defer {
							waiter = nil
						}
						switch w {
							case .synchronous(let oneShot):
								try! oneShot.fire(.success(element))
							case .asynchronous(let continuation):
								// handle the asynchronous waiter by resuming the continuation with the yielded element.
								// in this case, there is no need to interact with the pair, since the element is being passed directly to the waiter.
								continuation.resume(returning:.success(.success(element)))
						}
					case .none:
						try pair.addElement(elementCount:elementCount, element)
				}
			}

			internal mutating func consumeNext(elementCount:UnsafePointer<Atomic<UInt64>>) -> sending Element? {
				return pair.removeElement(elementCount:elementCount)
			}
		}
		internal struct State:~Copyable {
			internal var unfinished:Unfinished
			internal var capResult:Result<Void, Failure>? = nil
			internal init(maxElementsBuffered maxElements:UInt64?) {
				unfinished = Unfinished(maxElementsBuffered: maxElements)
			}
		}
	}

	private let count:Atomic<UInt64> = Atomic(0)
	private let core:Mutex<Core.State>

	internal init(maxElementsBuffered maxElements:UInt64?) {
		core = Mutex(.init(maxElementsBuffered: maxElements))
	}

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
		switch try core.withLock({ (state) throws(InvalidStateError) -> Core.Unfinished.WaiterInfo? in
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
			case .some(let waiter):
				switch waiter {
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
							// if the fifo has been finished, we must resume the continuation with nil, which indicates that the fifo has been finished.
							case .success:
								continuation.resume(returning:.success(nil))
							// if the fifo has been finished with an error, we must resume the continuation with the error, which indicates that the fifo has been finished with an error.
							case .failure(let error):
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

					// validate that there is no elements available.
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

	internal func nextSyncExplicit() throws(AlreadyWaiting) -> ConsumeResult {
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