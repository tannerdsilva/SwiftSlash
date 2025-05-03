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

/// Represents a unidirectional data channel that will connect to the launched process.
/// Channels can be fully handled by SwiftSlash, or delivered to `/dev/null`.
/// - NOTE: When SwiftSlash launches a process, the launched process is referred to as a *child* process.
public enum DataChannel:Sendable {

	/// Child process will be configured to write data.
	case write(ChildWrite)
	/// Child process will be configured to read data.
	case read(ChildRead)

	/// Represents the various ways that a child process can be configured to write data.
	public enum ChildWrite:Sendable {
	
		/// Asynchronous sequence of byte-array chunks produced by a child process.
		///
		/// Each `Element` is a `[[UInt8]]`, representing one or more raw data buffers.
		public struct ParentRead:Sendable, AsyncSequence {
			public enum Error:Swift.Error {}
			
			public typealias Element = [[UInt8]]
			
			/// Create a new data channel for child-to-parent streaming.
			public init() {}
	
			/// Returns an async iterator yielding data chunks until the channel closes.
			public borrowing func makeAsyncIterator() -> AsyncIterator {
				AsyncIterator(fifo.makeAsyncConsumerExplicit())
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
		
		/// Parent will actively capture the written contents of the child process and parse it by a predetermined separator.
		///
		/// - Parameters:
		/// 	- stream: The `ChildWrite` instance to consume the written data.
		/// 	- separator: Byte sequence used to delimit chunks (e.g. `[0x0A]` for newline).
		case toParentProcess(stream:ParentRead, separator:[UInt8])
		
		/// Discards child output on this data channel by piping it to `/dev/null`.
		/// The written data from the child process never touches the parent process.
		case toNull
	}

	/// Represents the various ways that a child process can be configured to read data.
	public enum ChildRead:Sendable {
		/// A writable channel that the parent process can use to send data for the child process to read.
		public struct ParentWrite:Sendable {
			public enum Error:Swift.Error {
				/// The channel was closed before or during a write.
				case dataChannelClosed
			}
			/// Internal FIFO for buffering outgoing data and completion futures.
			internal let fifo:FIFO<([UInt8], Future<Void, Error>?), Never> = .init()
	
			/// Initializes a new parent-to-child data channel.
			public init() {}
			
			/// Writes a byte buffer into the channel and optionally signals completion.
			///
			/// - Parameters:
			/// 	- element: The bytes to send.
			/// 	- future: Optional `Future` to fulfill on write completion or failure.
			public borrowing func yield(_ element:consuming [UInt8], future:Future<Void, Error>?) {
				switch fifo.yield((element, future)) {
					case .success:
						break
					case .fifoClosed:
						// Channel closed; report error if a future was provided.
						if future != nil {
							try? future!.setFailure(DataChannel.ChildRead.ParentWrite.Error.dataChannelClosed)
						}
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
		
		/// The parent process will be engaged with this data channel with the ability to write data for the child to read.
		///
		/// - Parameter stream: The `ChildRead` instance to send data into.
		case fromParentProcess(stream:ParentWrite)

		/// Provides no data by piping from `/dev/null`.
		/// The child sees an open channel but reads nothing.
		case fromNull
	}
}