#if os(Linux)
import Glibc
#elseif os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#endif

/// Not relevant for most applications. ChildSignalCatcher is used to capture exit code and status information from child processes.
///
/// **You are advised to NOT interact with the global ChildSignalCatcher unless you know it is necessary - 99% of developers wont need this.**
///
/// SwiftSlash asks other code in your application to abide by the following rules:
///   - Do NOT register a SIGCHLD  handler with the system (as this would override the handler that SwiftSlash registers with the system)
///   - Do NOT call `waitpid` against any children of your process (as this would interfere with SwiftSlash's ability to reap and terminate processes)
///
/// In return for following these rules, SwiftSlash offers the global `ChildSignalCatcher` instance which features:
///   - Shared access to the same mechanism that SwiftSlash uses for its own process-reaping function.
///   - Unfiltered access to the raw exit status values of every child PID of your process (whether they be SwiftSlash processes or other children)
///
public actor ChildSignalCatcher {
    /// The global instance for your application
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
    
    /// An async code block that handles `SIGCHLD` events with associated values passed as arguments
	public typealias SignalHandler = (pid_t, Int32) async -> Void
    /// A unique identifier for hander blocks registered with the `ChildSignalCatcher`
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
    
    /// Add a handler to the event stack
    /// - Parameter handler: the Handler block to execute when your application is sent a SIGCHLD signal
    /// - Returns: `SignalHandle` representing the unique ID for the registration. This value is used to deregister event handlers in the future.
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
    
    /// Deregister a code block from the event stack
    /// - Parameter handle: The unique ID representing the code block that is to be removed from the event handlers stack
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
