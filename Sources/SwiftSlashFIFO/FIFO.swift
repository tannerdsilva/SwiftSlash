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

	/// initialize a new FIFO with no maximum element count.
	public init() {
		datachain_primitive_ptr = __cswiftslash_fifo_init(true)
	}

	/// pass an element into the FIFO for consumption. the element will be held until it is consumed by the consumer. if the FIFO is closed, the element will be held until the FIFO is deinitialized. if a maximum element count was set, the element will be immediately discarded if the FIFO is full.
	@discardableResult public func yield(_ element:consuming Element) -> YieldResult {
		let um = Unmanaged.passRetained(Contained(element))
		
		#if DEBUG
		var i:UInt8 = 0
		#endif
		
		repeat {
			#if DEBUG
			defer {
				i += 1
			}
			guard i < 255 else {
				fatalError("swiftslash - yield infinite loop - \(#file):\(#line)")
			}
			#endif
			switch __cswiftslash_fifo_pass(datachain_primitive_ptr, um.toOpaque()) {
				// success return
				case 0:
					return .success

				// the FIFO is closed
				case -1:
					_ = um.takeRetainedValue()
					return .fifoClosed

				// the FIFO is full
				case -2:
					_ = um.takeRetainedValue()
					return .fifoFull

				// try again
				case 1:
				continue
				default:
					fatalError("swiftslash - unexpected return value from _cwskit_dc_pass - \(#file):\(#line)")
			}
		} while true
	}

	/// finish the FIFO. after calling this function, the FIFO will not accept any more data. additional objects may be passed into the FIFO, and they will be held and eventually dereferenced when the FIFO is deinitialized.
	public func finish() {
		let resultElement = Unmanaged.passRetained(Contained<Result<Void, Failure>>(.success(())))
		guard __cswiftslash_fifo_pass_cap(datachain_primitive_ptr, resultElement.toOpaque()) == true else {
			_ = resultElement.takeRetainedValue()
			return
		}
	}

	/// finish the FIFO. after calling this function, the FIFO will not accept any more data. additional objects may be passed into the FIFO, and they will be held and eventually dereferenced when the FIFO is deinitialized.
	public func finish(throwing finishingError:Failure) {
		let resultElement = Unmanaged.passRetained(Contained<Result<Void, Failure>>(.failure(finishingError)))
		guard __cswiftslash_fifo_pass_cap(datachain_primitive_ptr, resultElement.toOpaque()) == true else {
			_ = resultElement.takeRetainedValue()
			return
		}
	}

	deinit {
		var items = [UnsafeMutableRawPointer]()
		let capPointer:(Bool, UnsafeMutableRawPointer?) = withUnsafeMutablePointer(to:&items) { itemsPointer in
			var capPtr:UnsafeMutableRawPointer? = nil
			return (__cswiftslash_fifo_close(datachain_primitive_ptr, { pointer, ctx in
				ctx!.assumingMemoryBound(to:[UnsafeMutableRawPointer].self).pointee.append(pointer)
			}, itemsPointer, &capPtr), capPtr)
		}
		for item in items {
			_ = Unmanaged<Contained<Element>>.fromOpaque(item).takeRetainedValue()
		}
		if capPointer.0 == true && capPointer.1 != nil {
			_ = Unmanaged<Contained<Result<Void, Failure>>>.fromOpaque(capPointer.1!).takeRetainedValue()
		}
	}
}

extension FIFO {
	/// create a new consumer for the FIFO. this should be the only consumer for the FIFO, as the FIFO is not intended for use with multiple consumers.
	public func makeAsyncConsumer() -> Consumer {
		return Consumer(self)
	}

	/// the primary structure for consuming elements from the FIFO.
	public struct Consumer {
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
		public func next(whenTaskCancelled cancelAction:consuming WhenConsumingTaskCancelled = .noAction) async throws(Failure) -> Element? {
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

extension FIFO.Consumer {
	fileprivate func _next() async -> Result<Element?, Failure> {
		return await withUnsafeContinuation({ (continuation:UnsafeContinuation<Result<Element?, Failure>, Never>) in
			var pointer:__cswiftslash_ptr_t? = nil
			switch __cswiftslash_fifo_consume_blocking(fifo.datachain_primitive_ptr, &pointer) {
				case  __CSWIFTSLASH_FIFO_CONSUME_RESULT:
					continuation.resume(returning:.success(Unmanaged<Contained<Element>>.fromOpaque(pointer!).takeRetainedValue().value()))
				case  __CSWIFTSLASH_FIFO_CONSUME_CAP:
					switch Unmanaged<Contained<Result<Void, Failure>>>.fromOpaque(pointer!).takeUnretainedValue().value() {
						case .success:
							continuation.resume(returning:.success(nil))
						case .failure(let err):
							continuation.resume(returning:.failure(err))
					}
				case  __CSWIFTSLASH_FIFO_CONSUME_WOULDBLOCK:
					fatalError("swiftslash - got FIFO_CONSUME_WOULDBLOCK from _cswiftslash_fifo_consume_blocking - \(#file):\(#line)")
				case  __CSWIFTSLASH_FIFO_CONSUME_INTERNAL_ERROR:
					fatalError("swiftslash - got FIFO_CONSUME_INTERNAL_ERROR from _cswiftslash_fifo_consume_blocking - \(#file):\(#line)")
				default:
					fatalError("swiftslash - unexpected return value from _cswiftslash_fifo_consume_blocking - \(#file):\(#line)")
			}
		})
	}
}