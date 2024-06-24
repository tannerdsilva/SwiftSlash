// import ClibSwiftSlash
// import Foundation
import Logging

internal enum EventMode {
	case readableEvent(Int)
	case writableEvent
	case readingClosed
	case writingClosed
}

internal struct EventDescription {
	internal let fh:Int32
	internal let event:EventMode
}

public protocol EventTrigger {
	func register(reader:Int32) throws
	func register(writer:Int32) throws
	func deregister(reader:Int32) throws
	func deregister(writer:Int32) throws
	associatedtype EventTriggerHandle

	static func run() async throws
}

// #if os(Linux)
// import Glibc
// internal struct EventTrigger {
// 	internal static func launchNew() -> EventTrigger {
// 		let newET = EventTrigger()
// 		DispatchQueue(label:"com.swiftslash.event-trigger").async {
// 			newET._mainLoop()
// 		}
// 		return newET
// 	}
// 	enum Error:Swift.Error {
// 		case unableToRegister
// 	}
	
// 	fileprivate let epoll = epoll_create1(0);
	
// 	internal let eventStream:AsyncStream<EventDescription>
	
// 	fileprivate let eventContinuation:AsyncStream<EventDescription>.Continuation
	
// 	fileprivate init() {
// 		var eventCont:AsyncStream<EventDescription>.Continuation? = nil
// 		self.eventStream = AsyncStream<EventDescription> { cont in
// 			eventCont = cont
// 		}
// 		self.eventContinuation = eventCont!
// 	}
	
// 	fileprivate func _mainLoop() {
// 		var epollEventsAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:32)
// 		defer {
// 			epollEventsAllocation.deallocate()
// 		}
// 		var allocationSize:Int32 = 32
// 		func reallocate(size:Int32) {
// 			epollEventsAllocation.deallocate()
// 			epollEventsAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:Int(size))
// 			allocationSize = size
// 		}
		
// 		while true {
// 			let pollResult = epoll_wait(epoll, epollEventsAllocation, allocationSize, -1) 
// 			switch pollResult {
// 				case -1:
// 					if (errno != EINTR) {
// 						fatalError("EPOLL ERROR")
// 					}
// 					break;
// 				default:
// 					if (pollResult > 0) {
// 						var i = 0
// 						while (i < pollResult) {
// 							let currentEvent = epollEventsAllocation[i]
// 							let pollin = currentEvent.events & UInt32(EPOLLIN.rawValue)
// 							let pollhup = currentEvent.events & UInt32(EPOLLHUP.rawValue)
// 							let pollout = currentEvent.events & UInt32(EPOLLOUT.rawValue)
// 							let pollerr = currentEvent.events & UInt32(EPOLLERR.rawValue)
							
// 							if (pollhup != 0) {
// 								//reading handle closed
// 								try? self.deregister(reader:currentEvent.data.fd)
// 								self.eventContinuation.yield((EventDescription(fh:currentEvent.data.fd, event:.readingClosed)))
// 							} else if (pollerr != 0) {
// 								//writing handle closed
// 								try? self.deregister(writer:currentEvent.data.fd)
// 								self.eventContinuation.yield((EventDescription(fh:currentEvent.data.fd, event:.writingClosed)))
// 							} else if (pollin != 0) {
// 								//read data available
// 								var byteCount:Int = 0
// 								guard ioctl(currentEvent.data.fd, UInt(FIONREAD), &byteCount) == 0 else {
// 									fatalError("EventTrigger ioctl error")
// 								}
// 								self.eventContinuation.yield((EventDescription(fh:currentEvent.data.fd, event:.readableEvent(byteCount))))
// 							} else if (pollout != 0) {
// 								//writing available
// 								self.eventContinuation.yield((EventDescription(fh:currentEvent.data.fd, event:.writableEvent)))
// 							}
// 							i = i + 1
// 						}
// 						if (i*2 > allocationSize) {
// 							reallocate(size:allocationSize*2)
// 						}
// 					}
// 			}
// 		}
// 	}
	
// 	func register(reader:Int32) throws {
// 		var buildEvent = epoll_event()
// 		buildEvent.data.fd = reader
// 		buildEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
// 		guard epoll_ctl(self.epoll, EPOLL_CTL_ADD, reader, &buildEvent) == 0 else {
// 			throw Error.unableToRegister
// 		}
// 	}
	
// 	func register(writer:Int32) throws {
// 		var buildEvent = epoll_event()
// 		buildEvent.data.fd = writer
// 		buildEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
// 		guard epoll_ctl(self.epoll, EPOLL_CTL_ADD, writer, &buildEvent) == 0 else {
// 			throw Error.unableToRegister
// 		}
// 	}
	
// 	func deregister(reader:Int32) throws {
// 		var buildEvent = epoll_event()
// 		buildEvent.data.fd = reader
// 		buildEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
// 		guard epoll_ctl(self.epoll, EPOLL_CTL_DEL, reader, &buildEvent) == 0 else {
// 			throw Error.unableToRegister
// 		}
// 	}
	
// 	func deregister(writer:Int32) throws {
// 		var buildEvent = epoll_event()
// 		buildEvent.data.fd = writer
// 		buildEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
// 		guard epoll_ctl(self.epoll, EPOLL_CTL_DEL, writer, &buildEvent) == 0 else {
// 			throw Error.unableToRegister
// 		}
// 	}
// }
// #elseif os(macOS)
import Glibc
// swiftslash is using pthread for the runtime loop that captures events from the kernel. this is so that the thread can be canceled while also using an indefinite wait time in the system polling call.
internal struct PThread:~Copyable {
	/// thrown when a pthread cannot be created.
	internal struct LaunchError:Swift.Error {}

	/// main function that handles the unwrapping of the logger before calling the main function.
	private static func mainWrapper(_ ptr:UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
		let unmanaged = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(ptr)
		var logger = unmanaged.takeUnretainedValue().getLogger()
		let tid = pthread_self()
		logger[metadataKey:"pthread_id"] = "\(tid)"
		logger.debug("pthread launched")
		do {
			try unmanaged.takeUnretainedValue().getRunFunction()(logger)
		} catch is CancellationError {
			logger.error("pthread canceled")
		} catch {
			logger.error("pthread error: \(error)")
		}
		pthread_exit(unmanaged.toOpaque())
	}

	/// the pthread primitive.
	private let pt_primitive:UnsafeMutablePointer<pthread_t>

	internal init(logger:consuming Logger, _ f:@escaping (borrowing Logger) throws -> Void) throws {
		let pthread = UnsafeMutablePointer<pthread_t>.allocate(capacity:1)
		let configPtr = Unmanaged.passRetained(PThread.ContainedConfiguration(logger, run:f))
		guard pthread_create(pthread, nil, { Self.mainWrapper($0!) }, configPtr.toOpaque()) != 0 && pthread != nil else {
			_ = configPtr.takeRetainedValue()
			throw LaunchError()
		}
		self.pt_primitive = pthread
	}



	internal consuming func cancel() {
		guard pthread_cancel(pt_primitive.pointee) == 0 else {
			fatalError("pthread_cancel error \(errno) from \(#file):\(#line)")
		}
	}

	deinit {
		var retPtr:UnsafeMutableRawPointer? = nil
		guard pthread_join(pt_primitive.pointee, &retPtr) == 0 else {
			fatalError("pthread_join error \(errno) from \(#file):\(#line)")
		}
		_ = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(retPtr!).takeRetainedValue()
	}
}

extension PThread {
	/// this class is used to pass a logger to the pthread in a relatively swift-friedly way.
	internal final class ContainedConfiguration {
		private let logger:Logger
		private let runFunc:(borrowing Logger) throws -> Void
		internal init(_ logger:Logger, run runFunc:@escaping (borrowing Logger) throws -> Void) {
			self.logger = logger
			self.runFunc = runFunc
		}
		internal func getLogger() -> Logger {
			return logger
		}
		internal func getRunFunction() -> (borrowing Logger) throws -> Void {
			return runFunc
		}
	}
}

// internal struct EventTrigger:~Copyable {
// 	internal typealias QueueType = Int32
//     enum Error:Swift.Error {
//         case unableToRegister
//     }

//     fileprivate let queue:QueueType
//     internal let eventStream:NAsyncStream<EventDescription>
// 	internal var thread:PThread

//     fileprivate init() throws {
// 		let newQueue = kqueue()
// 		self.queue = newQueue
// 		var ptLogger = Logger(label:"pthread")
// 		ptLogger.logLevel = .trace
// 		let newES = NAsyncStream<EventDescription>()
// 		self.eventStream = newES
// 		let newThread = try PThread(logger:ptLogger) { [es = newES, q = newQueue] threadLogger in
// 			threadLogger.notice("event trigger launched")
// 			defer {
// 				threadLogger.notice("event trigger terminated")
// 			}
// 			var allocationSize:Int32 = 32
// 			var kqueueEventsAllocation = UnsafeMutablePointer<kevent>.allocate(capacity:Int(allocationSize))
// 			defer {
// 				kqueueEventsAllocation.deallocate()
// 			}
// 			func reallocate(size:Int32) {
// 				threadLogger.debug("reallocating kqueue events buffer size to \(size)")
// 				kqueueEventsAllocation.deallocate()
// 				allocationSize = size
// 				kqueueEventsAllocation = UnsafeMutablePointer<kevent>.allocate(capacity:Int(allocationSize))
// 			}

// 			do {
// 				while true {
// 					let kqueueResult = kevent(q, nil, 0, kqueueEventsAllocation, allocationSize, nil)
// 					switch kqueueResult {
// 						case -1:
// 							guard errno != EINTR else {
// 								throw CancellationError()
// 							}
// 						case 0..<Int32.max:
// 							var i = 0
// 							while i < kqueueResult {
// 								let currentEvent = kqueueEventsAllocation[i]
// 								let kqueueClosed = currentEvent.flags & UInt16(EV_EOF)

// 								let curIdent = Int32(currentEvent.ident)
// 								if kqueueClosed == 0 {
// 									if currentEvent.filter == Int16(EVFILT_READ) {
// 										es.yield(EventDescription(fh:curIdent, event: .readableEvent(currentEvent.data)))
// 									} else if currentEvent.filter == Int16(EVFILT_WRITE) {
// 										es.yield(EventDescription(fh:curIdent, event: .writableEvent))
// 									}
// 								} else {
// 									if currentEvent.filter == Int16(EVFILT_READ) {
// 										try? Self.deregister(reader: curIdent, queue:q)
// 										es.yield(EventDescription(fh:curIdent, event: .readingClosed))
// 									} else if currentEvent.filter == Int16(EVFILT_WRITE) {
// 										try? Self.deregister(writer: curIdent, queue:q)
// 										es.yield(EventDescription(fh:curIdent, event: .writingClosed))
// 									}
// 								}
// 								i = i + 1
// 							}
// 							if (i*2 > allocationSize) {
// 								reallocate(size:allocationSize*2)
// 							}
// 						default:
// 							fatalError("epoll error - this should never happen")
// 					}
// 				}
// 			} catch is CancellationError {
// 				threadLogger.notice("event trigger canceled")
// 			} catch {
// 				threadLogger.error("event trigger error: \(error)")
// 			}
// 		}
// 		self.thread = newThread
// 	}
    
//     func register(reader:Int32) throws {
//         var newEvent = kevent()
//         newEvent.ident = UInt(reader)
//         newEvent.flags = UInt16(EV_ADD | EV_CLEAR | EV_EOF)
//         newEvent.filter = Int16(EVFILT_READ)
//         newEvent.fflags = 0
//         newEvent.data = 0
//         newEvent.udata = nil
//         guard kevent(queue, &newEvent, 1, nil, 0, nil) == 0 else {
//             throw Error.unableToRegister
//         }
//     }
    
//     func register(writer:Int32) throws {
//         var newEvent = kevent()
//         newEvent.ident = UInt(writer)
//         newEvent.flags = UInt16(EV_ADD | EV_CLEAR | EV_EOF)
//         newEvent.filter = Int16(EVFILT_WRITE)
//         newEvent.fflags = 0
//         newEvent.data = 0
//         newEvent.udata = nil
//         guard kevent(queue, &newEvent, 1, nil, 0, nil) == 0 else {
//             throw Error.unableToRegister
//         }
//     }
    
//     static func deregister(reader:Int32, queue:QueueType) throws {
//         var newEvent = kevent()
//         newEvent.ident = UInt(reader)
//         newEvent.flags = UInt16(EV_DELETE | EV_CLEAR | EV_EOF)
//         newEvent.filter = Int16(EVFILT_READ)
//         newEvent.fflags = 0
//         newEvent.data = 0
//         newEvent.udata = nil
//         guard kevent(queue, &newEvent, 1, nil, 0, nil) == 0 else {
//             throw Error.unableToRegister
//         }
//     }
    
//     static func deregister(writer:Int32, queue:QueueType) throws {
//         var newEvent = kevent()
//         newEvent.ident = UInt(writer)
//         newEvent.flags = UInt16(EV_DELETE | EV_CLEAR | EV_EOF)
//         newEvent.filter = Int16(EVFILT_WRITE)
//         newEvent.fflags = 0
//         newEvent.data = 0
//         newEvent.udata = nil
//         guard kevent(queue, &newEvent, 1, nil, 0, nil) == 0 else {
//             throw Error.unableToRegister
//         }
//     }
// }
// #endif