import Foundation

public struct DataChannel {

	//readable
	public struct Inbound:Hashable {
		public enum ParseMode {
			case cr
			case lf
			case crlf
			case unparsedRaw
		}
		public enum Configuration {
			case active(ParseMode)
			case closed
			case nullPipe
		}
		
		public var targetHandle:Int32
		
		public var stream:AsyncStream<Data>
		public var config:Configuration
		public var parseMode:ParseMode? {
			get {
				switch self.config {
					case let .active(mode):
					return mode
					default:
					return nil
				}
			}
		}
		public var continuation:AsyncStream<Data>.Continuation
		
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
	
	//writable
	public struct Outbound:Hashable {
		public enum Configuration {
			case active
			case closed
			case nullPipe
		}
		
		public var targetHandle:Int32
		
		public var stream:AsyncStream<Data>
		public var config:Configuration
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