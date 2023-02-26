import Foundation

/// DataChannels define how data is piped in and out of the process while it is running.
///  - Data channels are assigned to a file handle of the launched process
public struct DataChannel {
    
    /// Inbound DataChannels are for configuring channels that the running process will write to.
    /// - Inbound DataChannels are most commonly used to capture `STDOUT` and `STDERR` of the running process.
    public struct Inbound:Hashable {
        /// Used on active inbound channels to define how data is buffered and grouped into the AsyncStream
		public enum ParseMode {
            /// Separate  AsyncStream data chunks by the CR byte (0xD)
			case cr
            /// Separate  AsyncStream data chunks by the LF byte (0xA)
			case lf
            /// Separate  AsyncStream data chunks by the occurrence of the CRLF byte sequence (0xD followed by 0xA)
			case crlf
            /// Disable bytestream parsing. Data will be transparently passed to the AsyncStream in real time.
			case unparsedRaw
        }
		
        /// Defines the configuration for an Inbound data channel
		public enum Configuration {
            /// Actively capture the output from this data channel with the specified ``DataChannel/Inbound/ParseMode``. Data from this channel can be consumed through its `AsyncStream`.
			case active(ParseMode)
            /// Close the file handle of the running process at launch time
			case closed
            /// Map this file handle to `/dev/null`
			case nullPipe
		}
		
        /// The file handle that this data channel will be assigned on the running process
		public var targetHandle:Int32
		
        /// The stream of data that the running process is writing to this data stream (only useful on active configurations)
		public var stream:AsyncStream<Data>
        
        /// The configuration for this data channel
		public var config:Configuration
		internal var parseMode:ParseMode? {
			get {
				switch self.config {
					case let .active(mode):
					return mode
					default:
					return nil
				}
			}
		}
		internal var continuation:AsyncStream<Data>.Continuation
		
		public init(target:Int32, config:Configuration = .active(.lf)) {
			var continuation:AsyncStream<Data>.Continuation? = nil
			self.stream = AsyncStream<Data> { cont in
				continuation = cont
			}
			self.continuation = continuation!
			self.config = config
			switch config {
				case .closed, .nullPipe:
					continuation!.finish()
				case .active:
					break;
			}
			self.targetHandle = target
		}
		
		public func hash(into hasher:inout Hasher) {
			hasher.combine(targetHandle)
		}
		
		public static func == (lhs:Inbound, rhs:Inbound) -> Bool {
			return lhs.targetHandle == rhs.targetHandle
		}
	}
    
    /// Outbound DataChannels are for configuring channels that the running process will read from
    ///  - Outbound DataChannels are most commonly used to write data to `STDIN` of a running process.
	public struct Outbound:Hashable {
		public enum Configuration {
            /// Enable this file handle for data transfer with the running process through its AsyncStream.Continuation
			case active
            /// Close the file handle of the running process at launch time
			case closed
            /// Map this file handle to `/dev/null`
			case nullPipe
		}
        /// The file handle that this data channel will be assigned on the running process
		public var targetHandle:Int32
		
		internal var stream:AsyncStream<Data>
        
        /// The configuration for this data channel
		public var config:Configuration
        
        /// Submits data to enter the input stream of the running process
		public var continuation:AsyncStream<Data>.Continuation
		
		public init(target:Int32, config:Configuration = .active) {
			var continuation:AsyncStream<Data>.Continuation? = nil
			self.stream = AsyncStream<Data> { cont in
				continuation = cont
			}
			self.continuation = continuation!
			self.config = config
			switch config {
				case .closed, .nullPipe:
					continuation!.finish()
				case .active:
					break;
			}
			self.targetHandle = target
		}
		
		public func hash(into hasher:inout Hasher) {
			hasher.combine(targetHandle)
		}
		
		public static func == (lhs:Outbound, rhs:Outbound) -> Bool {
			return lhs.targetHandle == rhs.targetHandle
		}
	}
}
