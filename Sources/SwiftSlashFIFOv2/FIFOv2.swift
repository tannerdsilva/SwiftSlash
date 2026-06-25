/* LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Synchronization

#if os(macOS)
import struct Darwin.pthread_mutex_t
import func Darwin.pthread_mutex_unlock
import func Darwin.pthread_mutex_lock
import func Darwin.pthread_mutex_init
import func Darwin.pthread_mutex_destroy
#elseif os(Linux)
// will be handled later
#endif

/// fifo is a mechanism that operates very similarly to a native Swift AsyncStream. the tool is designed for use with a single producer and a single consumer. the tool is thread-safe and reentrancy-safe, but is not intended for use with multiple producers or multiple consumers.
public final class FIFOv2<Element:~Copyable, Failure>:Sendable where Failure:Swift.Error {
	
	/// used to convey one of the possible outcomes of consuming the next element from the FIFO.
	public enum ConsumeResult:~Copyable {
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
		/// used to hold a pair of references to the base and tail links of the FIFO.
		internal struct ReferencePair:~Copyable {
			/// a reference to the base link of the FIFO
			internal var base:Link? = nil
			/// a reference to the tail link of the FIFO
			internal var tail:Link? = nil
		}
		/// used to set a limit of buffered elements in the FIFO. if this value is nil, the FIFO buffer size will be unbounded.
		internal let maxElementsBuffered:UInt64?
		/// used to track the number of elements currently buffered in the FIFO.
		internal var elementCount:UInt64 = 0
		/// used to track whether the FIFO has been closed. if the FIFO is closed, no more elements may be yielded into the FIFO.
		internal var pair:ReferencePair = ReferencePair()
		internal init(maxElementsBuffered maxElements:UInt64?) {
			maxElementsBuffered = maxElements
		}
	}

	internal final class Link {
		internal let element:Element
		internal var next:Link? = nil
		internal init(_ elementIn:consuming Element) {
			element = elementIn
		}
	}

	private let core:Mutex<Core> = Mutex(Core(maxElementsBuffered:nil))
	private let waiter:SyncWaiter
}