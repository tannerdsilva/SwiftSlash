import SwiftSlashNAsyncStream
import SwiftSlashFIFO
import SwiftSlashFuture

/// represents a uni-directional stream of data that can exist between a parent process and a child process. A data channel can only be one of two possible types...`ChildWriteParentRead` or `ChildReadParentWrite`.
public enum DataChannel {

	case childWriting(ChildWriteParentRead.Configuration)
	case childReading(ChildReadParentWrite.Configuration)

	// used for reading data that a running process writes.
	public struct ChildWriteParentRead:Sendable {

		/// specifies a configuration for an inbound data channel.
		public enum Configuration {
			/// configure the child process to write to this data channel as this running process reads from it.
			/// - parameters:
			/// 	1. the line separator to use when reading the data from the channel.
			case active(ChildWriteParentRead, [UInt8])
			/// configure the swiftslash to pipe this data channel to /dev/null. the running process will see the channel as open, any data it writes will go directly to /dev/null (never touches the parent process). as such, the parent process has no associated work to do in this configuration.
			case nullPipe

			/// returns a new configuration with unix-style line parsing `\n` aka `0x0A`
			internal static func createDefaultConfiguration() -> Configuration {
				return .active(.init(), [0x0A])
			}
		}

		// the underlying nasyncstream that this struct wraps
		internal let nasync:NAsyncStream<[UInt8], Never> = .init()

		public struct AsyncIterator:~Copyable {
			private let nasync:NAsyncStream<[UInt8], Never>.Consumer

			internal init(nasync:consuming NAsyncStream<[UInt8], Never>.Consumer) {
				self.nasync = nasync
			}

			public borrowing func next() async -> [UInt8]? {
				return await nasync.next(whenTaskCancelled:.finish)
			}
		}

		public borrowing func makeAsyncConsumer() -> NAsyncStream<[UInt8], Never>.Consumer {
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
	public struct ChildReadParentWrite:Sendable {

		/// specifies a configuration for an outbound data channel.
		public enum Configuration {
			/// configure the swiftslash to write to this data channel as the running process reads from it.
			case active(ChildReadParentWrite)
			/// configure the swiftslash to pipe this data channel to /dev/null. the running process will see the channel as open, any data it reads will come directly from /dev/null. as such, the parent process has no associated work to do in this configuration.
			case nullPipe
		}

		// the underlying nasyncstream that this struct wraps
		private let fifo:FIFO<([UInt8], Future<Void, WrittenDataChannelClosureError>?), Never> = .init()

		// create a new outbound data channel
		public borrowing func yield(_ element:consuming [UInt8], future:Future<Void, WrittenDataChannelClosureError>?) {
			fifo.yield((element, future))
		}

		// finish writing to the channel
		public borrowing func finish() {
			fifo.finish()
		}

		internal borrowing func makeAsyncConsumer() -> FIFO<([UInt8], Future<Void, WrittenDataChannelClosureError>?), Never>.AsyncConsumer {
			return fifo.makeAsyncConsumer()
		}
	}
}