/* LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Synchronization
import SwiftSlashOneShotLatch

extension FIFOv2 {
	/// the "internal core" mechanism of the FIFO.
	internal struct Core:~Copyable {
		/// thrown when the fifo is full and cannot accept any more elements.
		internal struct BufferLimitExceeded:Swift.Error {}

		/// the state of the FIFO. this state is used to track whether the FIFO has been closed, and to hold the unfinished state of the FIFO.
		internal struct State:~Copyable {
			/// the unfinished state of the FIFO. this is the state that is used to pass elements through the FIFO.
			internal var unfinished:Unfinished
			/// the result of the FIFO. if this value is non-nil, the FIFO has been closed and no more elements may be yielded into the FIFO.
			internal var capResult:Result<Void, Failure>? = nil
			/// initialize the state with an optional maximum element count.
			/// - parameter maxElements: the maximum number of elements that may be buffered in the FIFO. if this value is nil, the FIFO will be unbounded.
			/// - throws: InvalidMaximumElementCount if the maxElements parameter is 0.
			internal init(maxElementsBuffered maxElements:UInt64?) throws(InvalidMaximumElementCount) {
				unfinished = try Unfinished(maxElementsBuffered: maxElements)
			}
		}
	}
}

extension FIFOv2.Core.State {
	/// the unfinished state of the FIFO. this is the state that is used to pass elements through the FIFO.
	/// - NOTE: the unfinished state does not keep track of whether or not the FIFO has been closed.
	internal struct Unfinished:~Copyable {
		
		/// used to hold a pair of references to the base and tail links of the FIFO.
		/// NOTE: this struct does not concern itself with whether or not the FIFO has been closed. it is only used to hold the links that are used to bufffer and pass elements through the FIFO.
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
			internal mutating func addElement(elementCount:UnsafePointer<Atomic<UInt64>>, _ link:Element) throws(FIFOv2.Core.BufferLimitExceeded) {
				guard maxElementsBuffered == nil || elementCount.pointee.load(ordering:.sequentiallyConsistent) < maxElementsBuffered! else {
					throw FIFOv2.Core.BufferLimitExceeded()
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

		/// specifies one of the two kinds of waiters that can exist for the next fifo element.
		internal enum WaiterInfo:Sendable {
			/// a synchronous waiter is a one-shot latch that will be fired when the next element is available.
			case synchronous(OneShotLatch<FIFOv2.NextElement>)
			/// an asynchronous waiter is a continuation that will be resumed when the next element is available.
			case asynchronous(UnsafeContinuation<Result<FIFOv2.NextElement, FIFOv2.AlreadyWaiting>, Never>)
		}

		/// specifies one of the two possible outcomes of a yield operation.
		internal enum YieldResult:Sendable {
			/// the element was buffered in the FIFO, and there was no pending waiter to notify.
			case buffered
			/// the element was not buffered in the FIFO, because there was a pending waiter that was notified with the result of the yield operation. the holder of this value should notify the waiter with the provided result.
			case waiterNotificationRequired(WaiterInfo, FIFOv2.NextElement)
		}

		/// used to track whether the FIFO has been closed. if the FIFO is closed, no more elements may be yielded into the FIFO.
		private var pair:ReferencePair

		/// there may be a single waiter for the FIFO. if there is a waiter, it will be stored here. if there is no waiter, this value will be nil.
		/// - NOTE: a waiter must only be a non-nil value if the FIFO is empty. if the FIFO is not empty, there should be no waiter, and this value should be nil.
		internal var waiter:WaiterInfo? = nil

		/// initialize the Unfinished state with an optional maximum element count.
		/// - parameter maxElements: the maximum number of elements that may be buffered in the FIFO. if this value is nil, the FIFO will be unbounded.
		/// - throws: InvalidMaximumElementCount if the maxElements parameter is 0.
		internal init(maxElementsBuffered maxElements:UInt64?) throws(FIFOv2.InvalidMaximumElementCount) {
			guard maxElements != 0 else {
				throw FIFOv2.InvalidMaximumElementCount()
			}
			pair = ReferencePair(maxElementsBuffered: maxElements)
		}

		/// yields an element into the FIFO.
		/// - parameter element: the element to yield into the FIFO.
		/// - returns: a yield outcome that indicates whether the element was buffered in the FIFO, or whether there was a pending waiter that needs to be notified with the result of the yield operation.
		internal mutating func yield(elementCount:UnsafePointer<Atomic<UInt64>>, _ element:consuming Element) throws(FIFOv2.Core.BufferLimitExceeded) -> YieldResult {
			// if there is a waiter, we must notify them that an element is now available.
			switch waiter {
				case .some(let w):
					waiter = nil
					return .waiterNotificationRequired(w, .success(element))
				case .none:
					try pair.addElement(elementCount:elementCount, element)
					return .buffered
			}
		}

		/// consumes the next element from the FIFO.
		/// - returns: the next element from the FIFO, or nil if there is no element available.
		internal mutating func consumeNext(elementCount:UnsafePointer<Atomic<UInt64>>) -> sending Element? {
			return pair.removeElement(elementCount:elementCount)
		}
	}
}