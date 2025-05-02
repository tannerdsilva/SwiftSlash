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

/// Represents a unidirectional data channel between parent and child processes.
/// Use `childWriteParentRead` when the child writes data and the parent reads it.
/// Use `childReadParentWrite` when the parent writes data and the child reads it.
public enum DataChannel {

	/// Child process writes; parent process reads.
	case childWriteParentRead(ChildWriteParentRead.Configuration)
	/// Parent process writes; child process reads.
	case childReadParentWrite(ChildReadParentWrite.Configuration)

    /// Asynchronous sequence of byte-array chunks from the child process.
    ///
    /// Each element is `[[UInt8]]`, corresponding to parsed or raw buffers.
	public struct ChildWriteParentRead:Sendable, AsyncSequence {
		public enum Error:Swift.Error {}
		
        /// Returns an async iterator that yields data chunks as they arrive.
		public borrowing func makeAsyncIterator() -> AsyncIterator {
			return AsyncIterator(fifo.makeAsyncConsumerExplicit())
		}

		/// The type of element that this data channel will produce with each iteration.
		public typealias Element = [[UInt8]]

		/// Configuration for a channel where the child writes and the parent reads.
		public enum Configuration:Sendable {
			/// Active reader: child writes into this channel and the parent reads the written contents in real time.
			/// - Parameters:
			///   - stream: The `ChildWriteParentRead` instance to read from.
			///   - separator: Byte sequence used to delimit data chunks.
			case active(stream:ChildWriteParentRead, separator:[UInt8])
			/// Discards all child output by piping to `/dev/null`.
			/// The channel appears open, but data is dropped.
			case nullPipe

			/// Creates an active configuration using a custom or default newline separator.
			/// - Parameter separator: Optional byte-separator (default: `[0x0A]`).
			/// - Returns: A `.active` configuration with the specified separator.
			public static func createActiveConfiguration(separator:[UInt8]? = [0x0A]) -> Configuration {
				if separator != nil {
					return .active(stream:.init(), separator:separator!)
				} else {
					return .active(stream:.init(), separator:[0x0A])
				}
			}
		}

		/// the underlying nasyncstream that this struct wraps
		internal let fifo:FIFO<[[UInt8]], Never> = .init()

        /// Creates a new channel for child-to-parent data streaming.
		public init() {}

        /// Async iterator that consumes elements until the channel closes.
		public final class AsyncIterator:AsyncIteratorProtocol {
			private let fifoC:FIFO<[[UInt8]], Never>.AsyncConsumerExplicit
			internal init(_ fifo:consuming FIFO<[[UInt8]], Never>.AsyncConsumerExplicit) {
				fifoC = fifo
			}
            /// Returns the next chunk of data, or `nil` if the channel is closed.
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

        /// Yields a new element into the channel’s FIFO.
		internal borrowing func yield(_ element:consuming [[UInt8]]) {
			fifo.yield(element)
		}

        /// Finishes the channel, preventing further writes.
		/// - NOTE: The child process may to react to this event.
		internal borrowing func closeDataChannel() {
			fifo.finish()
		}
	}

	/// used for writing data that a running process reads.
	public struct ChildReadParentWrite:Sendable {
		public enum Error:Swift.Error {
			/// The channel was closed before or during a write.
			case dataChannelClosed
		}

		/// Configuration for a channel where the parent writes and the child reads.
		public enum Configuration:Sendable {
			/// Active writer: parent writes into this channel for the child to read.
			/// - Parameter stream: The `ChildReadParentWrite` instance to write into.
			case active(stream:ChildReadParentWrite)
			/// Provides no data (pipes from `/dev/null`).
			/// The child sees an open channel but reads nothing.
			case nullPipe
		}

		/// the underlying nasyncstream that this struct wraps
		internal let fifo:FIFO<([UInt8], Future<Void, DataChannel.ChildReadParentWrite.Error>?), Never> = .init()

		/// Creates a new channel for parent-to-child data streaming.
		public init() {}

		/// Writes a byte buffer into the channel and optionally signals completion via a future.
		///
		/// - Parameters:
		///   - element: The bytes to send.
		///   - future: Optional `Future` to fulfill when the write completes, or error if closed.
		public borrowing func yield(_ element:consuming [UInt8], future:Future<Void, DataChannel.ChildReadParentWrite.Error>?) {
			switch fifo.yield((element, future)) {
				case .success:
					// future successfully yielded, we can return.
					break
				case .fifoClosed:
					// the FIFO is closed, we cannot yield any more data. the future must be handled here if it is not nil.
					if future != nil {
						try? future!.setFailure(DataChannel.ChildReadParentWrite.Error.dataChannelClosed)
					}
				case .fifoFull:
					fatalError("SwiftSlashFIFO internal error :: FIFO is full, but not expecting to be working with a limited FIFO here. this is a critical error. \(#file):\(#line)")
			}
		}

		/// Closes the channel, indicating no more data will be sent.
		/// - NOTE: The child process may to react to this event.
		public borrowing func closeDataChannel() {
			fifo.finish()
		}

		/// Provides an asynchronous consumer for the channel’s byte buffers (internal use).
		internal borrowing func makeAsyncConsumer() -> FIFO<([UInt8], Future<Void, DataChannel.ChildReadParentWrite.Error>?), Never>.AsyncConsumerExplicit {
			return fifo.makeAsyncConsumerExplicit()
		}
	}
}