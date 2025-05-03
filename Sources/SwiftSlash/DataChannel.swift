/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import SwiftSlashFIFO
import SwiftSlashFuture

/// Represents a unidirectional data channel between processes.
/// Channels can be fully handled by SwiftSlash, delivered to `/dev/null`, or routed elsewhere.
/// In some configurations, the parent process may not read from or write to the channel at all.
public enum DataChannel:Sendable {

	/// Child writes into this channel; parent (or another consumer) may read.
	case childWriteParentRead(ChildWriteParentRead.Configuration)
	/// Parent (or another producer) writes into this channel; child reads.
	case childReadParentWrite(ChildReadParentWrite.Configuration)

	/// Asynchronous sequence of byte-array chunks produced by a child process.
	///
	/// Each `Element` is a `[[UInt8]]`, representing one or more raw data buffers.
	public struct ChildWriteParentRead: Sendable, AsyncSequence {
		public enum Error:Swift.Error {}

		public typealias Element = [[UInt8]]

		/// Create a new data channel for child-to-(parent or other) streaming.
		public init() {}

		/// Returns an async iterator yielding data chunks until the channel closes.
		public borrowing func makeAsyncIterator() -> AsyncIterator {
			AsyncIterator(fifo.makeAsyncConsumerExplicit())
		}

		/// Configuration options for this data channel.
		public enum Configuration:Sendable {
			/// Active channel: child writes into `stream` and data is delivered (to parent or other consumer).
			///
			/// - Parameters:
			/// 	- stream: The `ChildWriteParentRead` instance to receive data.
			/// 	- separator: Byte sequence used to delimit chunks (e.g. `[0x0A]` for newline).
			case active(stream:ChildWriteParentRead, separator:[UInt8])

			/// Discards all child output by piping it to `/dev/null`.
			/// The child sees an open channel, but no data is delivered to any consumer.
			case nullPipe

			/// Helper to create an active configuration using a custom or default newline separator.
			///
			/// - Parameter separator: Optional byte-separator (default: `[0x0A]`).
			/// - Returns: A `.active` configuration with the specified or default separator.
			public static func createActiveConfiguration(separator:[UInt8]? = nil) -> Configuration {
				return .active(stream:.init(), separator:separator ?? [0x0A])
			}
		}

		/// Internal FIFO for buffering incoming data.
		internal let fifo:FIFO<[[UInt8]], Never> = .init()

		/// Yields a new data chunk into the channel’s FIFO.
		internal borrowing func yield(_ element:consuming [[UInt8]]) {
			fifo.yield(element)
		}

		/// Closes the channel, signaling no further data.
		/// - Note: downstream consumers (e.g., parent or other) will see EOF.
		internal borrowing func closeDataChannel() {
			fifo.finish()
		}

		/// AsyncIterator for consuming data until the channel finishes.
		public final class AsyncIterator: AsyncIteratorProtocol {
			private let fifoC: FIFO<[[UInt8]], Never>.AsyncConsumerExplicit

			internal init(_ fifo: consuming FIFO<[[UInt8]], Never>.AsyncConsumerExplicit) {
				fifoC = fifo
			}

			/// Returns the next chunk of data, or `nil` when the channel is closed.
			public borrowing func next() async -> [[UInt8]]? {
				switch await fifoC.next(whenTaskCancelled:.finish) {
				case .element(let element):
					return element
				case .capped(_):
					return nil
				case .wouldBlock:
					fatalError("SwiftSlashFIFO internal error :: AsyncConsumer would block, but not expecting to be working with a limited FIFO here. this is a critical error. \(#file):\(#line)")
				}
			}
		}
	}

	// MARK: - ChildReadParentWrite

	/// Channel for sending data into a child process’s stdin (or another consumer).
	public struct ChildReadParentWrite:Sendable {
		public enum Error:Swift.Error {
			/// The channel was closed before or during a write.
			case dataChannelClosed
		}

		/// Configuration options for this outbound data channel.
		public enum Configuration:Sendable {
			/// Active channel: parent (or other producer) writes into `stream`, child reads.
			///
			/// - Parameter stream: The `ChildReadParentWrite` instance to send data into.
			case active(stream:ChildReadParentWrite)

			/// Provides no data by piping from `/dev/null`.
			/// The child sees an open channel but reads nothing.
			case nullPipe
		}

		/// Internal FIFO for buffering outgoing data and completion futures.
		internal let fifo:FIFO<([UInt8], Future<Void, DataChannel.ChildReadParentWrite.Error>?), Never> = .init()

		/// Initializes a new parent-to-child data channel.
		public init() {}

		/// Writes a byte buffer into the channel and optionally signals completion.
		///
		/// - Parameters:
		///   - element: The bytes to send.
		///   - future: Optional `Future` to fulfill on write completion or failure.
		public borrowing func yield(_ element:consuming [UInt8], future:Future<Void, DataChannel.ChildReadParentWrite.Error>?) {
			switch fifo.yield((element, future)) {
				case .success:
					break
				case .fifoClosed:
					// Channel closed; report error if a future was provided.
					future?.tryFailure(.dataChannelClosed)
				case .fifoFull:
					fatalError("SwiftSlashFIFO internal error :: FIFO is full, but not expecting to be working with a limited FIFO here. this is a critical error. \(#file):\(#line)")
			}
		}

		/// Closes the channel, indicating no further writes.
		/// - Note: child (or other consumer) will see EOF.
		public borrowing func closeDataChannel() {
			fifo.finish()
		}

		/// Provides an async consumer for the buffered data (internal use).
		internal borrowing func makeAsyncConsumer() -> FIFO<([UInt8], Future<Void, Error>?), Never>.AsyncConsumerExplicit {
			fifo.makeAsyncConsumerExplicit()
		}
	}
}