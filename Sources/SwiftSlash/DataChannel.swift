import SwiftSlashNAsyncStream

/// represents a uni-directional stream of data that can exist between a parent process and a child process.
public struct DataChannel {

	// used for reading data that a running process writes.
	public struct Inbound:AsyncSequence {

		/// specifies a configuration for an inbound data channel.
		public enum Configuration {
			/// configure the swiftslash to read this data channel as the running process writes to it.
			case active(Inbound)
			/// configure the swiftslash to close this data channel. the running process will see the channel as closed by the time it launches, and the parent process will have no associated work to do.
			case closed
			/// configure the swiftslash to pipe this data channel to /dev/null. the running process will see the channel as open, any data it writes will go directly to /dev/null (never touches the parent process). as such, the parent process has no associated work to do in this configuration.
			case nullPipe
		}

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

		/// specifies a configuration for an outbound data channel.
		public enum Configuration {
			/// configure the swiftslash to write to this data channel as the running process reads from it.
			case active(Outbound)
			/// configure the swiftslash to close this data channel. the running process will see the channel as closed by the time it launches, and the parent process will have no associated work to do.
			case closed
			/// configure the swiftslash to pipe this data channel to /dev/null. the running process will see the channel as open, any data it reads will come directly from /dev/null. as such, the parent process has no associated work to do in this configuration.
			case nullPipe
		}

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