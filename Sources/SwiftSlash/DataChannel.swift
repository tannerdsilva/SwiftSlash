import SwiftSlashNAsyncStream
import SwiftSlashFIFO
import SwiftSlashFuture

/// represents a uni-directional stream of data that can exist between a parent process and a child process.
public struct DataChannel {

	// used for reading data that a running process writes.
	public struct ChildWriteParentRead {

		/// specifies a configuration for an inbound data channel.
		public enum Configuration {
			/// configure the swiftslash to read this data channel as the running process writes to it.
			case active(ChildWriteParentRead, [UInt8])
			/// configure the swiftslash to pipe this data channel to /dev/null. the running process will see the channel as open, any data it writes will go directly to /dev/null (never touches the parent process). as such, the parent process has no associated work to do in this configuration.
			case nullPipe
		}

		// the underlying nasyncstream that this struct wraps
		internal let nasync:NAsyncStream<[UInt8], Never>

		public struct AsyncIterator:AsyncIteratorProtocol {
			private let nasync:NAsyncStream<[UInt8], Never>.AsyncConsumer

			internal init(nasync:NAsyncStream<[UInt8], Never>.AsyncConsumer) {
				self.nasync = nasync
			}

			public borrowing func next() async -> [UInt8]? {
				return await nasync.next(whenTaskCancelled:.finish)
			}
		}

		public borrowing func makeAsyncConsumer() -> NAsyncStream<[UInt8], Never>.AsyncConsumer {
			return nasync.makeAsyncConsumer()
		}

		internal borrowing func yield(_ element:consuming [UInt8]) {
			nasync.yield(element)
		}

		internal borrowing func finish() {
			nasync.finish()
		}
	}

	// used for writing data that a running process reads.
	public struct ChildReadParentWrite {

		/// specifies a configuration for an outbound data channel.
		public enum Configuration {
			/// configure the swiftslash to write to this data channel as the running process reads from it.
			case active(ChildReadParentWrite)
			/// configure the swiftslash to pipe this data channel to /dev/null. the running process will see the channel as open, any data it reads will come directly from /dev/null. as such, the parent process has no associated work to do in this configuration.
			case nullPipe
		}

		// the underlying nasyncstream that this struct wraps
		private let fifo:FIFO<([UInt8], Future<Void>?), Never>

		// create a new outbound data channel
		public borrowing func yield(_ element:consuming [UInt8], future:Future<Void>?) {
			fifo.yield((element, future))
		}

		// finish writing to the channel
		public borrowing func finish() {
			fifo.finish()
		}

		internal borrowing func makeAsyncConsumer() -> FIFO<([UInt8], Future<Void>?), Never>.AsyncConsumer {
			return fifo.makeAsyncConsumer()
		}
	}
}