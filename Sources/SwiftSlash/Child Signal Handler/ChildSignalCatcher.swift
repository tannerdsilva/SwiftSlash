#if os(Linux)
import Glibc
#elseif os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

public actor ChildSignalCatcher {
	public static let global = ChildSignalCatcher()
	fileprivate typealias MainSignalHandler = @convention(c)(Int32) -> Void
	fileprivate static let mainHandler:MainSignalHandler = { _ in
		var waitResult:pid_t = 0
		var status:Int32 = 0
		infiniteLoop: repeat {
			waitResult = waitpid(-1, &status, WNOHANG)
			if (waitResult > 0) {
				Task.detached { [waitResult, status] in
					for handler in await ChildSignalCatcher.global.handlerStack {
						await handler.handler(waitResult, status)
					}
				}
			} else {
				break infiniteLoop
			}
		} while true
	}
	
	public typealias SignalHandler = (pid_t, Int32) async -> Void
	public typealias SignalHandle = UInt64
	
	fileprivate struct KeyedHandler:Hashable{
		let handle:SignalHandle
		let handler:SignalHandler
		
		func hash(into hasher:inout Hasher) {
			hasher.combine(handle)
		}
		
		static func == (lhs:KeyedHandler, rhs:KeyedHandler) -> Bool {
			return lhs.handle == rhs.handle
		}
	}
	fileprivate var handlerStack = Set<KeyedHandler>()
	
	@discardableResult public func add(_ handler:@escaping(SignalHandler)) -> SignalHandle {
		let newID = SignalHandle.random(in:SignalHandle.min...SignalHandle.max)
		let newHandler = KeyedHandler(handle:newID, handler:handler)
		if handlerStack.count == 0 {
			reset(signal:SIGCHLD)
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
			var signalAction = sigaction(__sigaction_u:unsafeBitCast(ChildSignalCatcher.mainHandler, to:__sigaction_u.self), sa_mask:0, sa_flags:0)
			_ = withUnsafePointer(to:&signalAction) { handlerPointer in
				sigaction(SIGCHLD, handlerPointer.pointee, nil)
			}
#elseif os(Linux)
			var signalAction = sigaction()
			signalAction.__sigaction_handler = unsafeBitCast(ChildSignalCatcher.mainHandler, to:sigaction.__Unnamed_union___sigaction_handler.self)
			_ = sigaction(SIGCHLD, &signalAction, nil)	
#endif
		}
		handlerStack.update(with:newHandler)
		return newHandler.handle
	}
	
	public func remove(handle:SignalHandle) {
		self.handlerStack = self.handlerStack.filter({ $0.handle != handle })
		if (self.handlerStack.count == 0) {
			reset(signal:SIGCHLD)
		}
	}
	
	fileprivate func reset(signal:Int32) {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
		_ = Darwin.signal(signal, SIG_DFL)
#elseif os(Linux)
		_ = Glibc.signal(signal, SIG_DFL)		
#endif
	}
}
