import __cswiftslash

/// fifo is a mechanism that operates very similarly to a native Swift AsyncStream. the tool is designed for use with a single producer and a single consumer. the tool is thread-safe and reentrancy-safe, but is not intended for use with multiple producers or multiple consumers.
internal final class FIFO<T>:AsyncSequence, @unchecked Sendable {
	internal typealias Element = T

	private let stream:_Concurrency.AsyncStream<Void>
	private let continuation:_Concurrency.AsyncStream<Void>.Continuation
	private let datachain_primitive_ptr:UnsafeMutablePointer<_cswiftslash_fifo_linkpair_t>
	
	internal init() {
		let newPointer = UnsafeMutablePointer<_cswiftslash_fifo_linkpair_t>.allocate(capacity:1)
		var newMutex = _cswiftslash_fifo_mutex_new()
		newPointer.initialize(to:_cswiftslash_fifo_init(&newMutex))
		self.datachain_primitive_ptr = newPointer
		(self.stream, self.continuation) = _Concurrency.AsyncStream<Void>.makeStream(of:Void.self, bufferingPolicy:.bufferingOldest(1))
		self.continuation.onTermination = { [weak self] result in
			self!.finish()
		}
	}

	/// pass an element into the FIFO for consumption. the element will be held until it is consumed by the consumer. if the FIFO is closed, the element will be held until the FIFO is deinitialized.
	internal borrowing func yield(_ element:consuming T) {
		let um = Unmanaged.passRetained(ContainedItem(element))
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
				case 0:
					continuation.yield()
					return
				case -1:
					_ = um.takeRetainedValue()
					return
				case 1:
				continue
				default:
					fatalError("unexpected return value from _cwskit_dc_pass")
			}
		} while Task.isCancelled == false
	}

	/// finish the FIFO. after calling this function, the FIFO will not accept any more data. additional objects may be passed into the FIFO, and they will be held and eventually dereferenced when the FIFO is deinitialized.
	internal borrowing func finish(throwing finishingError:consuming Swift.Error) {
		let resultElement = Unmanaged.passRetained(ContainedResult(.failure(finishingError)))
		guard _cswiftslash_fifo_pass_cap(datachain_primitive_ptr, resultElement.toOpaque()) == true else {
			_ = resultElement.takeRetainedValue()
			return
		}
		continuation.finish()
	}

	/// finish the FIFO. after calling this function, the FIFO will not accept any more data. additional objects may be passed into the FIFO, and they will be held and eventually dereferenced when the FIFO is deinitialized.
	internal borrowing func finish() {
		let resultElement = Unmanaged.passRetained(ContainedResult(.success(())))
		guard _cswiftslash_fifo_pass_cap(datachain_primitive_ptr, resultElement.toOpaque()) == true else {
			_ = resultElement.takeRetainedValue()
			return
		}
		continuation.finish()
	}

	deinit {
		self.continuation.onTermination = nil
		if let capPointer = _cswiftslash_fifo_close(datachain_primitive_ptr, { pointer in 
			_ = Unmanaged<ContainedItem>.fromOpaque(pointer).takeRetainedValue()
		}) {
			_ = Unmanaged<ContainedResult>.fromOpaque(capPointer).takeRetainedValue()
		}
		datachain_primitive_ptr.deinitialize(count:1).deallocate()
	}
}

extension FIFO {
	private final class ContainedItem {
		private let stored:T
		internal init(_ storeItem:T) {
			self.stored = storeItem
		}
		internal func getStored() -> T {
			return stored
		}
	}
	private final class ContainedResult {
		private let stored:Result<Void, Swift.Error>
		internal init(_ storeItem:Result<Void, Swift.Error>) {
			self.stored = storeItem
		}
		internal func getStored() -> Result<Void, Swift.Error> {
			return stored
		}
	}

	/// call this function to become the exclusive consumer for a FIFO. the returned object will be used to consume the FIFO.
	internal func makeAsyncIterator() -> AsyncIterator {
		return AsyncIterator(self)
	}

	internal struct AsyncIterator:AsyncIteratorProtocol {
	    internal mutating func next() async throws -> T? {
			var pointer:_cswiftslash_ptr_t? = nil
			#if DEBUG
			var i:UInt8 = 0
			#endif
			repeat {
				#if DEBUG
				defer {
					i += 1
				}
				guard i < 255 else {
					fatalError("next infinite loop")
				}
				#endif
				switch _cswiftslash_fifo_consume_nonblocking(fifo.datachain_primitive_ptr, &pointer) {
					case 0:
						let um = Unmanaged<ContainedItem>.fromOpaque(pointer!)
						return um.takeRetainedValue().getStored()
					case 1:
						let um = Unmanaged<ContainedResult>.fromOpaque(pointer!)
						let result = um.takeUnretainedValue().getStored()
						switch result {
							case .success:
								return nil
							case .failure(let err):
								throw err
						}
					case -1:
						_ = await self.streamIterator.next()
						continue
					case -2:
						fatalError("an internal error was encountered while consuming datachain")
					default:
						fatalError("unexpected return value from _cwskit_dc_consume_nonblocking")
				} 
			} while true
		}

	    internal typealias Element = T

		private let fifo:FIFO<T>
		private var streamIterator:_Concurrency.AsyncStream<Void>.AsyncIterator

		internal init(_ fifo:FIFO<T>) {
			self.fifo = fifo
			self.streamIterator = fifo.stream.makeAsyncIterator()
		}
	}
}