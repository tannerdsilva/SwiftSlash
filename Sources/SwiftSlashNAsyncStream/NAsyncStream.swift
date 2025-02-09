import SwiftSlashFIFO
import SwiftSlashIdentifiedList

/// NAsyncStream is a scratch-built concurrency paradigm built to function nearly identically to a traditional Swift AsyncStream. there are some key differences and simplifications that make NAsyncStream easier to use and more flexible than a traditional AsyncStream. NAsyncStream facilitates any number of producers and guarantees delivery to n number of pre-registered consumers. the tool is thread-safe and reentrancy-safe.
/// there is absolutely no formal ritual required to operante an NAsyncStream. simply create a new instance and start yielding data to it. consumers can be registered at any time with`makeAsyncIterator()` and will receive all data that is yielded to the stream after their registration. objects will be buffered indefinitely until they are consumed or the Iterator is dereferenced. data is not duplicated when it is yielded to the stream. the data is stored by reference to all consumers to reference back to.
/// NAsyncStream will buffer objects indefinitely until they are either consumed (by all registered consumers at the time of production) or the stream is dereferenced.
public struct NAsyncStream<Element, Failure>:Sendable {
	
	public func makeAsyncConsumer() -> AsyncConsumer {
		// each new consumer gets their own dedicated FIFO instance. that instance is initialized here.
		return AsyncConsumer(il:il, fifo:FIFO<Element, Failure>())
	}

	// this stores all of the consumers of the stream. each consumer has their own FIFO instance. this atomic list is used to access and manage the lifecycle of these consumers.
	private let il = IdentifiedList<FIFO<Element, Failure>>()

	/// initialize a new NAsyncStream instance.
	public init() {}

	/// pass data to all registered consumers of the stream.
	public borrowing func yield(_ data:consuming Element) {
		il.forEach({ [d = data] (_, fifo:FIFO<Element, Failure>) in
			fifo.yield(d)
		})
	}

	/// finish the stream. all consumers will be notified that the stream has finished.
	public borrowing func finish() {
		il.forEach({ _, fifo in
			fifo.finish()
		})
	}
}

extension NAsyncStream where Failure == Swift.Error {
	/// finish the stream with an error. all consumers will be notified that the stream has finished.
	public borrowing func finish(throwing err:consuming Swift.Error) {
		il.forEach({ [e = err] (_, fifo:FIFO<Element, Failure>) in
			fifo.finish(throwing:e)
		})
	}
}

extension NAsyncStream {
	/// the AsyncIterator for NAsyncStream. this is the object that consumers will use to access the data that is yielded to the stream.
	/// you can think of an AsyncIterator instance as a "personal ID card" for each consumer to access the data that is needs to consume.
	/// dereferencing the AsyncIterator will remove the consumer from the stream and free up any resources that were being used to buffer data for that consumer (if any).
	/// aside from being an internal mechanism for identifying each consumer (thereby allowing NAsyncStream a vehicle to facilitate guaranteed delivery of each yield to each individual consumer), there is no practical frontend use for the AsyncIterator.
	public final class AsyncConsumer {
		private let key:UInt64
		private var fifoC:FIFO<Element, Failure>.AsyncConsumer
		private let il:IdentifiedList<FIFO<Element, Failure>>
		internal init(il:IdentifiedList<FIFO<Element, Failure>>, fifo:FIFO<Element, Failure>) {
			self.key = il.insert(fifo)
			self.fifoC = fifo.makeAsyncConsumer()
			self.il = il
		}
		deinit {
			_ = il.remove(key)
		}
	}
}

extension NAsyncStream.AsyncConsumer where Failure == Never {
	/// get the next element from the stream. this is a blocking call. if there is no data available, the call will block until data is available.
	/// - returns: the next element in the stream.
	public func next(whenTaskCancelled cancelAction:consuming FIFO<Element, Failure>.WhenConsumingTaskCancelled) async -> Element? {
		return await fifoC.next(whenTaskCancelled:cancelAction)
	}
}

extension NAsyncStream.AsyncConsumer where Failure == Swift.Error {
	/// get the next element from the stream. this is a blocking call. if there is no data available, the call will block until data is available.
	/// - returns: the next element in the stream.
	public func next(whenTaskCancelled cancelAction:consuming FIFO<Element, Failure>.WhenConsumingTaskCancelled) async throws -> Element? {
		return try await fifoC.next(whenTaskCancelled:cancelAction)
	}
}