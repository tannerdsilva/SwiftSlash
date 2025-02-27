/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import SwiftSlashFIFO
import SwiftSlashIdentifiedList

/// NAsyncStream is a scratch-built concurrency paradigm built to function nearly identically to a traditional Swift AsyncStream. there are some key differences and simplifications that make NAsyncStream easier to use and more flexible than a traditional AsyncStream. NAsyncStream facilitates any number of producers and guarantees delivery to n number of pre-registered consumers. the tool is thread-safe and reentrancy-safe.
/// there is absolutely no formal ritual required to operante an NAsyncStream. simply create a new instance and start yielding data to it. consumers can be registered at any time with`makeAsyncConsumer()` and will receive all data that is yielded to the stream after their registration. objects will be buffered indefinitely until they are consumed or the Iterator is dereferenced. data is not duplicated when it is yielded to the stream. the data is stored by reference to all consumers to reference back to.
/// NAsyncStream will buffer objects indefinitely until they are either consumed (by all registered consumers at the time of production) or the stream is dereferenced.
public struct NAsyncStream<Element, Failure>:Sendable where Failure:Swift.Error {
	
	public func makeAsyncConsumer() -> Consumer {
		// each new consumer gets their own dedicated FIFO instance. that instance is initialized here.
		return Consumer(il:il, fifo:FIFO<Element, Failure>())
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

	/// finish the stream with an error. all consumers will be notified that the stream has finished.
	public borrowing func finish(throwing err:consuming Failure) {
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
	public struct Consumer:~Copyable {
		private let key:UInt64
		private let fifoC:FIFO<Element, Failure>.Consumer
		private let il:IdentifiedList<FIFO<Element, Failure>>
		internal init(il ilArg:IdentifiedList<FIFO<Element, Failure>>, fifo:FIFO<Element, Failure>) {
			key = ilArg.insert(fifo)
			fifoC = fifo.makeAsyncConsumer()
			il = ilArg
		}
		/// get the next element from the stream. this is a blocking call. if there is no data available, the call will block until data is available.
		/// - returns: the next element in the stream.
		public borrowing func next(whenTaskCancelled cancelAction:consuming FIFO<Element, Failure>.Consumer.WhenConsumingTaskCancelled = .noAction) async throws(Failure) -> Element? {
			return try await fifoC.next(whenTaskCancelled:cancelAction)
		}
		deinit {
			_ = il.remove(key)
		}
	}
}