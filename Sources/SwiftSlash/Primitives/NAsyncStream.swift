/// NAsyncStream is a scratch-built concurrency paradigm built to function nearly identically to a traditional Swift AsyncStream. there are some key differences and simplifications that make NAsyncStream significantly easier to use and more flexible than a traditional AsyncStream. NAsyncStream facilitates any number of producers and fully manages the object delivery to n number of consumers. the tool is thread-safe and reentrancy-safe.
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
	public func yield(_ data:T) {
		al.forEach({ [d = data] _, continuation in
			continuation.yield(d)
		})
	}

	/// finish the stream. all consumers will be notified that the stream has finished.
	public func finish() {
		al.forEach({ _, continuation in
			continuation.finish()
		})
	}

	/// finish the stream with an error. all consumers will be notified that the stream has finished.
	public func finish(throwing err:Swift.Error) {
		al.forEach({ [e = err] _, continuation in
			continuation.finish(throwing:e)
		})
	}
}

extension NAsyncStream {
	public final class AsyncIterator:AsyncIteratorProtocol {
		public func next() async throws -> Element? {
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