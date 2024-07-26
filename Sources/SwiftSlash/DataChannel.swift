import SwiftSlashNAsyncStream

public struct DataChannel {

	// used for reading
	public struct Inbound:AsyncSequence {

		// the underlying nasyncstream that this struct wraps
		private let nasync:NAsyncStream<[UInt8]>

		public typealias Element = [UInt8]
		public typealias AsyncIterator = NAsyncStream<[UInt8]>.AsyncIterator

		public borrowing func makeAsyncIterator() -> NAsyncStream<[UInt8]>.AsyncIterator {
			return nasync.makeAsyncIterator()
		}

		internal borrowing func yield(_ element:consuming [UInt8]) {
			nasync.yield(element)
		}

		internal borrowing func finish() {
			nasync.finish()
		}
	}

	// used for writing
	public struct Outbound {

		// the underlying nasyncstream that this struct wraps
		private let nasync:NAsyncStream<[UInt8]>

		public typealias Element = [UInt8]
		public typealias AsyncIterator = NAsyncStream<[UInt8]>.AsyncIterator

		// create a new outbound data channel
		public borrowing func yield(_ element:consuming [UInt8]) {
			nasync.yield(element)
		}

		// finish writing to the channel
		public borrowing func finish() {
			nasync.finish()
		}
	}
}