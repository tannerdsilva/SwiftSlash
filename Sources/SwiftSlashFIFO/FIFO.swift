import __cswiftslash
import SwiftSlashContained

/// fifo is a mechanism that operates very similarly to a native Swift AsyncStream. the tool is designed for use with a single producer and a single consumer. the tool is thread-safe and reentrancy-safe, but is not intended for use with multiple producers or multiple consumers.
public final class FIFO<T>:AsyncSequence, Sequence, @unchecked Sendable {
	public typealias Element = T

	private let maxElements:size_t?
	private let datachain_primitive_ptr:UnsafeMutablePointer<_cswiftslash_fifo_linkpair_t>
	
	/// initialize a new FIFO. an optional maximumElementCount may be passed to limit the number of elements that may be held in the FIFO at any given time.
	/// - parameters:
	///		- maximumElementCount: the maximum number of elements that may be held in the FIFO at any given time. if this value is nil, the FIFO will hold uint64.max elements.
	public init(maximumElementCount:size_t? = nil) {
		// memory setup
		var newMutex = _cswiftslash_fifo_mutex_new()
		let newPointer = UnsafeMutablePointer<_cswiftslash_fifo_linkpair_t>.allocate(capacity:1)
		newPointer.initialize(to:_cswiftslash_fifo_init(&newMutex))

		// set the maximum element count if it was passed
		if maximumElementCount != nil {
			#if DEBUG
			assert(_cswiftslash_fifo_set_max_elements(newPointer, maximumElementCount!) == true)
			#else
			_cswiftslash_fifo_set_max_elements(newPointer, maximumElementCount)
			#endif
		}

		datachain_primitive_ptr = newPointer
		maxElements = maximumElementCount
	}

	/// pass an element into the FIFO for consumption. the element will be held until it is consumed by the consumer. if the FIFO is closed, the element will be held until the FIFO is deinitialized. if a maximum element count was set, the element will be immediately discarded if the FIFO is full.
	public borrowing func yield(_ element:consuming T) {
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
				fatalError("yield infinite loop")
			}
			#endif
			switch _cswiftslash_fifo_pass(datachain_primitive_ptr, um.toOpaque()) {
				// success return
				case 0:
					return

				// the FIFO is closed
				case -1:
					_ = um.takeRetainedValue()
					return

				// the FIFO is full
				case -2:
					_ = um.takeRetainedValue()
					return

				// try again
				case 1:
				continue
				default:
					fatalError("unexpected return value from _cwskit_dc_pass")
			}
		} while Task.isCancelled == false
	}

	/// finish the FIFO. after calling this function, the FIFO will not accept any more data. additional objects may be passed into the FIFO, and they will be held and eventually dereferenced when the FIFO is deinitialized.
	public borrowing func finish(throwing finishingError:consuming Swift.Error) {
		let resultElement = Unmanaged.passRetained(Contained<Result<Void, Swift.Error>>(.failure(finishingError)))
		guard _cswiftslash_fifo_pass_cap(datachain_primitive_ptr, resultElement.toOpaque()) == true else {
			_ = resultElement.takeRetainedValue()
			return
		}
	}

	/// finish the FIFO. after calling this function, the FIFO will not accept any more data. additional objects may be passed into the FIFO, and they will be held and eventually dereferenced when the FIFO is deinitialized.
	public borrowing func finish() {
		let resultElement = Unmanaged.passRetained(Contained<Result<Void, Swift.Error>>(.success(())))
		guard _cswiftslash_fifo_pass_cap(datachain_primitive_ptr, resultElement.toOpaque()) == true else {
			_ = resultElement.takeRetainedValue()
			return
		}
	}

	deinit {
		if let capPointer = _cswiftslash_fifo_close(datachain_primitive_ptr, { pointer in 
			_ = Unmanaged<Contained<Element>>.fromOpaque(pointer).takeRetainedValue()
		}) {
			_ = Unmanaged<Contained<Result<Void, Swift.Error>>>.fromOpaque(capPointer).takeRetainedValue()
		}
	}
}

extension FIFO {
	/// call this function to become the exclusive consumer for a FIFO. the returned object will be used to consume the FIFO.
	public func makeAsyncIterator() -> AsyncIterator {
		return AsyncIterator(self)
	}

	public func makeIterator(shouldBlock:Bool) -> Iterator {
		return Iterator(self, shouldBlock:shouldBlock)
	}

	public func makeIterator() -> Iterator {
		return makeIterator(shouldBlock:false)
	}

	public struct Iterator:IteratorProtocol {
		public mutating func next() -> T? {
			var pointer:_cswiftslash_ptr_t? = nil

			switch shouldBlock {
				case true:
					switch _cswiftslash_fifo_consume_blocking(fifo.datachain_primitive_ptr, &pointer) {
						case FIFO_CONSUME_RESULT:
							return Unmanaged<Contained<Element>>.fromOpaque(pointer!).takeRetainedValue().value()
						case FIFO_CONSUME_CAP:
							switch Unmanaged<Contained<Result<Void, Swift.Error>>>.fromOpaque(pointer!).takeUnretainedValue().value() {
								case .success:
									return nil
								case .failure(let err):
									fatalError("unexpected error: \(err)")
							}
						case FIFO_CONSUME_WOULDBLOCK:
							fatalError("unexpected return value from _cswiftslash_fifo_consume_blocking \(#file):\(#line)")
						case FIFO_CONSUME_INTERNAL_ERROR:
							fatalError("an internal error was encountered while consuming datachain \(#file):\(#line)")
						default:
							fatalError("unexpected return value from _cswiftslash_fifo_consume_blocking \(#file):\(#line)")
					}
				case false:
					switch _cswiftslash_fifo_consume_nonblocking(fifo.datachain_primitive_ptr, &pointer) {
						case FIFO_CONSUME_RESULT:
							return Unmanaged<Contained<Element>>.fromOpaque(pointer!).takeRetainedValue().value()
						case FIFO_CONSUME_CAP:
							switch Unmanaged<Contained<Result<Void, Swift.Error>>>.fromOpaque(pointer!).takeUnretainedValue().value() {
								case .success:
									return nil
								case .failure(let err):
									fatalError("unexpected error: \(err)")
							}
						case FIFO_CONSUME_WOULDBLOCK:
							return nil
						case FIFO_CONSUME_INTERNAL_ERROR:
							fatalError("an internal error was encountered while consuming datachain")
						default:
							fatalError("unexpected return value from _cwskit_dc_consume_nonblocking")
					}
			}
		}

		public typealias Element = T

		private let fifo:FIFO<T>
		private let shouldBlock:Bool

		public init(_ fifo:FIFO<T>, shouldBlock:Bool) {
			self.fifo = fifo
			self.shouldBlock = shouldBlock
		}
	}

	public struct AsyncIterator:AsyncIteratorProtocol {
	    public mutating func next() async throws -> T? {
			var pointer:_cswiftslash_ptr_t? = nil
			return try await withUnsafeThrowingContinuation { (continuation:UnsafeContinuation<T?, Swift.Error>) in
				switch _cswiftslash_fifo_consume_blocking(fifo.datachain_primitive_ptr, &pointer) {
					case FIFO_CONSUME_RESULT:
						continuation.resume(returning:Unmanaged<Contained<Element>>.fromOpaque(pointer!).takeRetainedValue().value())
					case FIFO_CONSUME_CAP:
						switch Unmanaged<Contained<Result<Void, Swift.Error>>>.fromOpaque(pointer!).takeUnretainedValue().value() {
							case .success:
								continuation.resume(returning:nil)
							case .failure(let err):
								continuation.resume(throwing:err)
						}
					case FIFO_CONSUME_WOULDBLOCK:
						fatalError("unexpected return value from _cwskit_dc_consume_blocking")
					case FIFO_CONSUME_INTERNAL_ERROR:
						fatalError("an internal error was encountered while consuming datachain")
					default:
						fatalError("unexpected return value from _cwskit_dc_consume_nonblocking")
				}
			}
		}

	    public typealias Element = T

		private let fifo:FIFO<T>

		public init(_ fifo:FIFO<T>) {
			self.fifo = fifo
		}
	}
}