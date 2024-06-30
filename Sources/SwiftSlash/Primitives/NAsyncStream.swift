/// NAsyncStream is a scratch-built concurrency paradigm built to function nearly identically to a traditional Swift AsyncStream. there are some key differences and simplifications that make NAsyncStream easier to use and more flexible than a traditional AsyncStream. NAsyncStream facilitates any number of producers and guarantees delivery to n number of pre-registered consumers. the tool is thread-safe and reentrancy-safe.
/// there is absolutely no formal ritual required to operante an NAsyncStream. simply create a new instance and start yielding data to it. consumers can be registered at any time with`makeAsyncIterator()` and will receive all data that is yielded to the stream after their registration. objects will be buffered indefinitely until they are consumed or the Iterator is dereferenced. data is not duplicated when it is yielded to the stream. the data is stored by reference to all consumers to reference back to.
/// NAsyncStream will buffer objects indefinitely until they are either consumed or the stream is dereferenced.
public struct NAsyncStream<T>:AsyncSequence, Sendable {
	public typealias Element = T
	public func makeAsyncIterator() -> AsyncIterator {
		// each new consumer gets their own dedicated FIFO instance. that instance is initialized here.
		return AsyncIterator(al:al, fifo:FIFO<T>())
	}

	// this stores all of the consumers of the stream. each consumer has their own FIFO instance. this atomic list is used to access and manage the lifecycle of these consumers.
	private let al = AtomicList<FIFO<T>>()

	/// initialize a new NAsyncStream instance.
	public init() {}

	/// pass data to all registered consumers of the stream.
	public borrowing func yield(_ data:consuming T) {
		al.forEach({ [d = data] _, continuation in
			continuation.yield(d)
		})
	}

	/// finish the stream. all consumers will be notified that the stream has finished.
	public borrowing func finish() {
		al.forEach({ _, continuation in
			continuation.finish()
		})
	}

	/// finish the stream with an error. all consumers will be notified that the stream has finished.
	public borrowing func finish(throwing err:consuming Swift.Error) {
		al.forEach({ [e = err] _, continuation in
			continuation.finish(throwing:e)
		})
	}
}

extension NAsyncStream {
	/// the AsyncIterator for NAsyncStream. this is the object that consumers will use to access the data that is yielded to the stream.
	/// you can think of an AsyncIterator instance as a "personal ID card" for each consumer to access the data that is needs to consume.
	/// dereferencing the AsyncIterator will remove the consumer from the stream and free up any resources that were being used to buffer data for that consumer (if any).
	/// aside from being an internal mechanism for identifying each consumer (thereby allowing NAsyncStream a vehicle to facilitate guaranteed delivery of each yield to each individual consumer), there is no practical frontend use for the AsyncIterator.
	public final class AsyncIterator:AsyncIteratorProtocol {
		public borrowing func next() async throws -> Element? {
			return try await fifo.next()
		}
		public typealias Element = T
		private let key:UInt64
		private var fifo:FIFO<T>.AsyncIterator
		private let al:AtomicList<FIFO<T>>
		internal init(al:AtomicList<FIFO<Element>>, fifo:FIFO<Element>) {
			self.key = al.insert(fifo)
			self.fifo = fifo.makeAsyncIterator()
			self.al = al
		}
		deinit {
			_ = al.remove(key)
		}
	}
}