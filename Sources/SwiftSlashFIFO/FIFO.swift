/* LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_fifo
import SwiftSlashContained

/// fifo is a mechanism that operates very similarly to a native Swift AsyncStream. the tool is designed for use with a single producer and a single consumer. the tool is thread-safe and reentrancy-safe, but is not intended for use with multiple producers or multiple consumers.
public final class FIFO<Element, Failure>:@unchecked Sendable where Failure:Swift.Error {
	
	public enum YieldResult {
		/// the yield value was successfully passed into the FIFO
		case success
		/// the FIFO was closed, and the yield value was not passed into the FIFO
		case fifoClosed
		/// the FIFO was full, and the yield value was not passed into the FIFO
		case fifoFull
	}
	
	// underlying c implementation
	private let datachain_primitive_ptr:UnsafeMutablePointer<__cswiftslash_fifo_linkpair_t>
	
	/// initialize a new FIFO with a specified maximum element count.
	/// - parameters:
	///		- maximumElementCount: the maximum number of elements that may be held in the FIFO at any given time.
	public init(maximumElementCount:size_t) {
		// memory setup
		let newPointer = __cswiftslash_fifo_init(true)

		// set the maximum element count if it was passed
		guard __cswiftslash_fifo_set_max_elements(newPointer, maximumElementCount) == true else {
			fatalError("swiftslash - failed to set maximum element count - \(#file):\(#line)")
		}
		datachain_primitive_ptr = newPointer
	}

	/// initialize a new FIFO with no maximum element count. yielded elements will be retained indefinitely until they are consumed or the FIFO is deinitialized.
	public init() {
		datachain_primitive_ptr = __cswiftslash_fifo_init(true)
	}

	/// pass an element into the FIFO for consumption. the element will be held until it is consumed by the consumer. if the FIFO is closed, the element will be held until the FIFO is deinitialized. if a maximum element count was set, the element will be immediately discarded if the FIFO is full.
	@discardableResult public borrowing func yield(_ element:consuming Element) -> YieldResult {
		let um = Unmanaged.passRetained(Contained(element)).toOpaque()
		passLoop: repeat {
			logicSwitch: switch __cswiftslash_fifo_pass(datachain_primitive_ptr, um) {
				// try again
				case 1:
					break logicSwitch

				// success return
				case 0:
					return .success

				// the FIFO is closed
				case -1:
					_ = Unmanaged<Contained<Element>>.fromOpaque(um).takeRetainedValue()
					return .fifoClosed

				// the FIFO is full
				case -2:
					_ = Unmanaged<Contained<Element>>.fromOpaque(um).takeRetainedValue()
					return .fifoFull
				default:
					fatalError("swiftslash - unexpected return value from __cswiftslash_fifo_pass - \(#file):\(#line)")
			}
		} while true
	}

	/// finish the FIFO. after calling this function, the FIFO will not accept any more data. additional objects may be passed into the FIFO, and they will be held and eventually dereferenced when the FIFO is deinitialized.
	public borrowing func finish() {
		let resultElement = Unmanaged.passRetained(Contained<Result<Void, Failure>>(.success(())))
		guard __cswiftslash_fifo_pass_cap(datachain_primitive_ptr, resultElement.toOpaque()) == true else {
			_ = resultElement.takeRetainedValue()
			return
		}
	}

	/// finish the FIFO. after calling this function, the FIFO will not accept any more data. additional objects may be passed into the FIFO, and they will be held and eventually dereferenced when the FIFO is deinitialized.
	public borrowing func finish(throwing finishingError:consuming Failure) {
		let resultElement = Unmanaged.passRetained(Contained<Result<Void, Failure>>(.failure(finishingError)))
		guard __cswiftslash_fifo_pass_cap(datachain_primitive_ptr, resultElement.toOpaque()) == true else {
			_ = resultElement.takeRetainedValue()
			return
		}
	}

	deinit {
		// close the fifo and capture the various pointers that are being held and returned by this function.
		var items = [UnsafeMutableRawPointer]()
		let capPointer:(Bool, UnsafeMutableRawPointer?) = withUnsafeMutablePointer(to:&items) { itemsPointer in
			var capPtr:UnsafeMutableRawPointer? = nil
			return (__cswiftslash_fifo_close(datachain_primitive_ptr, { pointer, ctx in
				ctx!.assumingMemoryBound(to:[UnsafeMutableRawPointer].self).pointee.append(pointer)
			}, itemsPointer, &capPtr), capPtr)
		}
		// consume a reference to each of the items that were being held by the FIFO
		for item in items {
			_ = Unmanaged<Contained<Element>>.fromOpaque(item).takeRetainedValue()
		}
		// consume the cap pointer if it was returned
		if capPointer.0 == true && capPointer.1 != nil {
			_ = Unmanaged<Contained<Result<Void, Failure>>>.fromOpaque(capPointer.1!).takeRetainedValue()
		}
	}
}

extension FIFO {
	public func makeSyncConsumerNonBlocking() -> SyncConsumerNonBlocking {
		return SyncConsumerNonBlocking(self)
	}

	public struct SyncConsumerNonBlocking:~Copyable {
		private let fifo:FIFO<Element, Failure>
		internal init(_ fifoIn:consuming FIFO) {
			fifo = fifoIn
		}

		public borrowing func next() throws(Failure) -> Element? {
			return try _next()?.get()
		}
	}
}

extension FIFO {
	public func makeSyncConsumerBlocking() -> SyncConsumerBlocking {
		return SyncConsumerBlocking(self)
	}

	public struct SyncConsumerBlocking:~Copyable {
		private let fifo:FIFO<Element, Failure>
		internal init(_ fifoIn:consuming FIFO) {
			fifo = fifoIn
		}

		public borrowing func next() throws(Failure) -> Element? {
			return try _next().get()
		}
	}
}

extension FIFO {
	/// create a new consumer for the FIFO. this should be the only consumer for the FIFO, as the FIFO is not intended for use with multiple consumers.
	public func makeAsyncConsumer() -> AsyncConsumer {
		return AsyncConsumer(self)
	}

	/// the primary structure for consuming elements from the FIFO.
	public struct AsyncConsumer:~Copyable {
		/// specifies the action to take when a task is cancelled while consuming the FIFO.
		public enum WhenConsumingTaskCancelled {
			/// when the current task is cancelled, the FIFO will not be affected. no actions will be taken.
			case noAction
			/// when the current task is cancelled, the FIFO will be finished.
			case finish
		}

		/// the FIFO being consumed
		private let fifo:FIFO<Element, Failure>

		/// initialize a new consumer for the specified FIFO.
		internal init(_ fifoIn:consuming FIFO) {
			fifo = fifoIn
		}

		/// wait asyncronously for the next element to consume from the FIFO.
		public borrowing func next(whenTaskCancelled cancelAction:consuming WhenConsumingTaskCancelled = .noAction) async throws(Failure) -> Element? {
			switch cancelAction {
				case .noAction:
					return try await _next().get()
				case .finish:
					return try await withTaskCancellationHandler(operation: {
						await _next()
					}, onCancel: { [f = fifo] in
						f.finish()
					}).get()
			}
		}
	}
}

extension FIFO.SyncConsumerNonBlocking {
	fileprivate borrowing func _next() -> Result<Element?, Failure>? {
		var pointer:__cswiftslash_ptr_t? = nil
		return FIFO._handleFIFOConsume(__cswiftslash_fifo_consume_nonblocking(fifo.datachain_primitive_ptr, &pointer), pointer)
	}
}

extension FIFO.SyncConsumerBlocking {
	fileprivate borrowing func _next() -> Result<Element?, Failure> {
		var pointer:__cswiftslash_ptr_t? = nil
		return FIFO._handleFIFOConsume(__cswiftslash_fifo_consume_blocking(fifo.datachain_primitive_ptr, &pointer), pointer)!
	}
}

extension FIFO.AsyncConsumer {
	fileprivate borrowing func _next() async -> Result<Element?, Failure> {
		return await withUnsafeContinuation({ (continuation:UnsafeContinuation<Result<Element?, Failure>, Never>) in
			var pointer:__cswiftslash_ptr_t? = nil
			continuation.resume(returning:FIFO._handleFIFOConsume(__cswiftslash_fifo_consume_blocking(fifo.datachain_primitive_ptr, &pointer), pointer)!)
		})
	}
}

extension FIFO {
	fileprivate static func _handleFIFOConsume(_ ret:__cswiftslash_fifo_consume_result_t, _ pointer:__cswiftslash_ptr_t?) -> Result<Element?, Failure>? {
		switch ret {
			case  __CSWIFTSLASH_FIFO_CONSUME_RESULT:
				return .success(Unmanaged<Contained<Element>>.fromOpaque(pointer!).takeRetainedValue().value())
			case  __CSWIFTSLASH_FIFO_CONSUME_CAP:
				switch Unmanaged<Contained<Result<Void, Failure>>>.fromOpaque(pointer!).takeUnretainedValue().value() {
					case .success:
						return .success(nil)
					case .failure(let err):
						return .failure(err)
				}
			case  __CSWIFTSLASH_FIFO_CONSUME_WOULDBLOCK:
				return nil
			case  __CSWIFTSLASH_FIFO_CONSUME_INTERNAL_ERROR:
				fatalError("swiftslash - got FIFO_CONSUME_INTERNAL_ERROR from _cswiftslash_fifo_consume_blocking - \(#file):\(#line)")
			default:
				fatalError("swiftslash - unexpected return value from _cswiftslash_fifo_consume_blocking - \(#file):\(#line)")
		}
	}
}