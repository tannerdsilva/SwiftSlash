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

/// represents a uni-directional stream of data that can exist between a parent process and a child process. A data channel can only be one of two possible types...`ChildWriteParentRead` or `ChildReadParentWrite`.
public enum DataChannel {

	/// specifies a data channel that the child process will write to and the calling process will read from.
	case childWriteParentRead(ChildWriteParentRead.Configuration)
	/// specifies a data channel that the child process will read from and the calling process will write to.
	case childReadParentWrite(ChildReadParentWrite.Configuration)

	/// used for reading data that a running process writes.
	public struct ChildWriteParentRead:Sendable, AsyncSequence {
		/// returns an async iterator for this data channel.
		public borrowing func makeAsyncIterator() -> AsyncIterator {
			return AsyncIterator(fifo.makeAsyncConsumerExplicit())
		}

		/// the type of element that this data channel will produce with each iteration.
		public typealias Element = [[UInt8]]

		/// specifies a configuration for an inbound data channel.
		public enum Configuration:Sendable {
			/// configure the child process to write to this data channel as this running process reads from it.
			/// - parameters:
			/// 	- parameter stream: the stream that the child process will write to.
			/// 	- parameter separator: the byte sequence that will be used to separate the data chunks. this is used for line parsing. if this is not provided, the default value of `\n` aka `0x0A` will be used.
			case active(stream:ChildWriteParentRead, separator:[UInt8])
			/// configure the swiftslash to pipe this data channel to /dev/null. the running process will see the channel as open, any data it writes will go directly to /dev/null (never touches the parent process). as such, the parent process has no associated work to do in this configuration.
			case nullPipe

			/// returns a new configuration with unix-style line parsing `\n` aka `0x0A`
			public static func createActiveConfiguration(separator:[UInt8]? = nil) -> Configuration {
				if separator != nil {
					return .active(stream:.init(), separator:separator!)
				} else {
					return .active(stream:.init(), separator:[0x0A])
				}
			}
		}

		/// the underlying nasyncstream that this struct wraps
		internal let fifo:FIFO<[[UInt8]], Never> = .init()

		/// initialize a new data channel that the child process will write to and the calling process will read from.
		public init() {}

		/// AsyncIterator for consuming read data from the child process.
		public final class AsyncIterator:AsyncIteratorProtocol {
			private let fifoC:FIFO<[[UInt8]], Never>.AsyncConsumerExplicit
			internal init(_ fifo:consuming FIFO<[[UInt8]], Never>.AsyncConsumerExplicit) {
				fifoC = fifo
			}
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

		/// used for writing data that a running process reads.
		internal borrowing func yield(_ element:consuming [[UInt8]]) {
			fifo.yield(element)
		}

		/// finish writing to the channel so that no more data can be sent through it.
		internal borrowing func finish() {
			fifo.finish()
		}
	}

	/// used for writing data that a running process reads.
	public struct ChildReadParentWrite:Sendable {

		/// specifies a configuration for an outbound data channel.
		public enum Configuration:Sendable {
			/// configure the swiftslash to write to this data channel as the running process reads from it.
			case active(stream:ChildReadParentWrite)
			/// configure the swiftslash to pipe this data channel to /dev/null. the running process will see the channel as open, any data it reads will come directly from /dev/null. as such, the parent process has no associated work to do in this configuration.
			case nullPipe
		}

		/// the underlying nasyncstream that this struct wraps
		private let fifo:FIFO<([UInt8], Future<Void, WrittenDataChannelClosureError>?), Never> = .init()

		/// create a new outbound data channel
		public borrowing func yield(_ element:consuming [UInt8], future:Future<Void, WrittenDataChannelClosureError>?) {
			switch fifo.yield((element, future)) {
				case .success:
				break
				case .fifoClosed:
					// The FIFO is closed, we cannot yield any more data.
					if future != nil {
						try! future!.setFailure(WrittenDataChannelClosureError.dataChannelClosed)
					}
				case .fifoFull:
					fatalError("SwiftSlashFIFO internal error :: FIFO is full, but not expecting to be working with a limited FIFO here. this is a critical error. \(#file):\(#line)")
			}
		}

		/// finish writing to the channel
		public borrowing func finish() {
			fifo.finish()
		}

		/// AsyncConsumer for consuming written data from the child process.
		internal borrowing func makeAsyncConsumer() -> FIFO<([UInt8], Future<Void, WrittenDataChannelClosureError>?), Never>.AsyncConsumer {
			return fifo.makeAsyncConsumer()
		}
	}
}