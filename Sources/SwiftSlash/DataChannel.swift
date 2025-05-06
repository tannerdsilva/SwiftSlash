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
/// Data channels must be prepared for a child process **before** the process is launched.
/// - NOTE: When SwiftSlash launches a process, the launched process is referred to as a *child* process.
public enum DataChannel:Sendable {

	/// Child process will be configured to write data.
	case write(ChildWrite)
	/// Child process will be configured to read data.
	case read(ChildRead)

	/// Represents the various ways that a child process can be configured to write data.
	/// - NOTE: When SwiftSlash launches a process, the launched process is referred to as a *child* process.
	public enum ChildWrite:Sendable {
	
		/// Primary interface for consuming bytes written by child processes.
		public struct ParentRead:Sendable, AsyncSequence {
			public enum Error:Swift.Error {}
			
			/// Multiple lines or segments are grouped into a single array to reduce async context switching and ensure timely delivery of data.
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
			public struct AsyncIterator:AsyncIteratorProtocol {
				internal let fifo: FIFO<[[UInt8]], Never>.AsyncConsumerExplicit
				internal init(_ fifo:consuming FIFO<[[UInt8]], Never>.AsyncConsumerExplicit) {
					self.fifo = fifo
				}
				/// Returns the next chunk of data, or `nil` when the channel is closed.
				public borrowing func next() async -> [[UInt8]]? {
					switch await fifo.next(whenTaskCancelled:.finish) {
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
		/// The written data from the child process never reaches the parent process.
		case toNull
	}

	/// Represents the various ways that a child process can be configured to read data.
	/// - NOTE: When SwiftSlash launches a process, the launched process is referred to as a *child* process.
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
			
			/// Yields a sequence of bytes to be written for the child process to read. This function will return immediately and does not wait for the data to be flushed.
			/// - Parameters:
			/// 	- bytes: The bytes to send.
			/// - Throws: This function throws ``SwiftSlash/DataChannel/ChildRead/ParentWrite/Error`` if the data channel has already been closed.
			/// - NOTE: This function returns immediately.
			public borrowing func yield(_ bytes:consuming [UInt8]) throws(Error) {
				switch fifo.yield((bytes, nil)) {
					case .success:
						break;
					case .fifoClosed:
						throw Error.dataChannelClosed
					case .fifoFull:
						fatalError("SwiftSlashFIFO internal error :: FIFO is full, but not expecting to be working with a limited FIFO here. this is a critical error. \(#file):\(#line)")
				}
			}
			
			/// Writes a sequence of bytes for the child process to read. This function will not return until that data has been successfully flushed to the child process.
			/// - Pararmeters:
			/// 	- bytes: The bytes to send.
			/// - Throws: This function throws ``SwiftSlash/DataChannel/ChildRead/ParentWrite/Error`` if the data channel has already been closed.
			/// - NOTE: This function will not return until the data has been successfully flushed to the child process.
			public borrowing func write(_ bytes:consuming [UInt8]) async throws(Error) {
				let newFuture = Future<Void, Error>()
				switch fifo.yield((bytes, newFuture)) {
					case .success:
						try await newFuture.result()!.get()
					case .fifoClosed:
						throw Error.dataChannelClosed
					case .fifoFull:
						fatalError("SwiftSlashFIFO internal error :: FIFO is full, but not expecting to be working with a limited FIFO here. this is a critical error. \(#file):\(#line)")
				}
			}
	
			/// Closes the channel, indicating no further writes.
			/// - Note: child process will receive `EOF` and may react to this event.
			public borrowing func closeDataChannel() {
				fifo.finish()
			}
	
			/// Provides an async consumer for the buffered data to be consumed.
			internal borrowing func makeAsyncConsumer() -> FIFO<([UInt8], Future<Void, Error>?), Never>.AsyncConsumerExplicit {
				fifo.makeAsyncConsumerExplicit()
			}
		}
		
		/// The parent process will be bound to this data channel, having the ability to write data for the child to read.
		///
		/// - Parameter stream: The `ParentWrite` instance to send data into.
		case fromParentProcess(stream:ParentWrite)

		/// Child reads data sourced directly from `/dev/null` or equivalent source.
		case fromNull
	}
}
