import __cswiftslash
import SwiftSlashPThread

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

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

/// event trigger is an abstract term for a given platforms low-level event handling mechanism. this protocol is used to define the interface for the event trigger of each platform.
internal protocol EventTrigger:PThreadWork {

	/// registers a file handle (that is intended to be read from) with the event trigger for active monitoring.
	static func register(_ ev:EventTriggerHandle, reader:Int32) throws

	/// registers a file handle (that is intended to be written to) with the event trigger for active monitoring.
	static func register(_ ev:EventTriggerHandle, writer:Int32) throws

	/// deregisters a file handle. the reader must be of reader variant. if the handle is not of reader variant, behavior is undefined.
	static func deregister(_ ev:EventTriggerHandle, reader:Int32) throws

	/// deregisters a file handle. the handle must be of writer variant. if the handle is not of writer variant, behavior is undefined.
	static func deregister(_ ev:EventTriggerHandle, writer:Int32) throws
	
	/// the type of primitive that this particular event trigger uses.
	associatedtype EventTriggerHandle

	/// the primitive that is used to handle the event trigger.
	var prim:EventTriggerHandle { get set }
}

internal enum EventTriggerError:Swift.Error {
	case unableToRegister
}

#if os(Linux)
internal final class LinuxET {

	/// the primitive that is used to handle the event trigger.
	internal typealias Argument = Void
	/// the primitive that is used to handle the event trigger.
	internal typealias ReturnType = Void
	/// the primitive that is used to handle the event trigger.
	internal typealias EventTriggerHandle = Int32

	internal typealias EventType = epoll_event

	/// the primitive that is used to handle the event trigger.
	private var prim:EventTriggerHandle = epoll_create1(0)

	/// event buffer that allows us to process events.
	private var allocationSize:size_t = 32
	private var events:UnsafeMutablePointer<EventType> = UnsafeMutablePointer<EventType>.allocate(capacity:32)	// no need to initialize this since the Pointee type is a c struct.

	internal static func register(_ ev:EventTriggerHandle, reader:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = reader
		buildEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_ADD, reader, &buildEvent) == 0 else {
			throw EventTriggerError.unableToRegister
		}
	}

	internal static func register(_ ev:EventTriggerHandle, writer:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = writer
		buildEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_ADD, writer, &buildEvent) == 0 else {
			throw EventTriggerError.unableToRegister
		}
	}

	internal static func deregister(_ ev:EventTriggerHandle, reader:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = reader
		buildEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_DEL, reader, &buildEvent) == 0 else {
			throw EventTriggerError.unableToRegister
		}
	}

	internal static func deregister(_ ev:EventTriggerHandle, writer:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = writer
		buildEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_DEL, writer, &buildEvent) == 0 else {
			throw EventTriggerError.unableToRegister
		}
	}

	func runEventTrigger() throws {
		let epollET = epoll_wait(epoll, epollEventsAllocation, allocationSize, -1) 
	}

	deinit {
		close(prim)
		events.deallocate()	// no need to deinitialize since the Pointee type is a c struct.
	}
}
#elseif os(macOS)
internal final class MacOSET {
	
	/// the primitive that is used to handle the event trigger.
	internal typealias Argument = Void
	/// the primitive that is used to handle the event trigger.
	internal typealias ReturnType = Void
	/// the primitive that is used to handle the event trigger.
	internal typealias EventTriggerHandle = Int32

	internal typealias EventType = kevent

	/// the primitive that is used to handle the event trigger.
	private var prim:EventTriggerHandle = kqueue()

	/// event buffer that allows us to process events.
	private var allocationSize:Int32 = 32
	private var events:UnsafeMutablePointer<EventType> = UnsafeMutablePointer<EventType>.allocate(capacity:32)	// no need to initialize this since the Pointee type is a c struct.
	private func reallocate(size:Int32) {
		events.deallocate()
		allocationSize = size
		events = UnsafeMutablePointer<EventType>.allocate(capacity:Int(size))
	}

	// ai gen need to audit
	internal static func register(_ ev:EventTriggerHandle, reader:Int32) throws {
		var newEvent = kevent()
		newEvent.ident = UInt(reader)
		newEvent.flags = UInt16(EV_ADD | EV_CLEAR | EV_EOF)
		newEvent.filter = Int16(EVFILT_READ)
		newEvent.fflags = 0
		newEvent.data = 0
		newEvent.udata = nil
		guard kevent(ev, &newEvent, 1, nil, 0, nil) == 0 else {
			throw EventTriggerError.unableToRegister
		}
	}

	// ai gen need to audit
	internal static func register(_ ev:EventTriggerHandle, writer:Int32) throws {
		var newEvent = kevent()
		newEvent.ident = UInt(writer)
		newEvent.flags = UInt16(EV_ADD | EV_CLEAR | EV_EOF)
		newEvent.filter = Int16(EVFILT_WRITE)
		newEvent.fflags = 0
		newEvent.data = 0
		newEvent.udata = nil
		guard kevent(ev, &newEvent, 1, nil, 0, nil) == 0 else {
			throw EventTriggerError.unableToRegister
		}
	}

	// ai gen need to audit
	internal static func deregister(_ ev:EventTriggerHandle, reader:Int32) throws {
		var newEvent = kevent()
		newEvent.ident = UInt(reader)
		newEvent.flags = UInt16(EV_DELETE | EV_CLEAR | EV_EOF)
		newEvent.filter = Int16(EVFILT_READ)
		newEvent.fflags = 0
		newEvent.data = 0
		newEvent.udata = nil
		guard kevent(ev, &newEvent, 1, nil, 0, nil) == 0 else {
			throw EventTriggerError.unableToRegister
		}
	}

	internal static func deregister(_ ev:EventTriggerHandle, writer:Int32) throws {
		var newEvent = kevent()
		newEvent.ident = UInt(writer)
		newEvent.flags = UInt16(EV_DELETE | EV_CLEAR | EV_EOF)
		newEvent.filter = Int16(EVFILT_WRITE)
		newEvent.fflags = 0
		newEvent.data = 0
		newEvent.udata = nil
		guard kevent(ev, &newEvent, 1, nil, 0, nil) == 0 else {
			throw EventTriggerError.unableToRegister
		}
	}

	func pthreadWork() throws {
		let kqueueResult = kevent(prim, nil, 0, events, allocationSize, nil)
		switch kqueueResult {
			case Int32.min..<0:
				switch errno {
					case EINTR:
						pthread_testcancel()
					default:
						fatalError("kevent error - this should never happen")
				}
			case 0..<Int32.max:
				var i = 0
				while i < kqueueResult {
					let currentEvent = events[i]
					let curIdent = Int32(currentEvent.ident)
					if currentEvent.flags & UInt16(EV_EOF) == 0 {
						if currentEvent.filter == Int16(EVFILT_READ) {
							let ed = EventDescription(fh:curIdent, event: .readableEvent(currentEvent.data))
						} else if currentEvent.filter == Int16(EVFILT_WRITE) {
							let ed = EventDescription(fh:curIdent, event: .writableEvent)
						}
					} else {
						if currentEvent.filter == Int16(EVFILT_READ) {
							try? Self.deregister(prim, reader: curIdent)
							let ed = EventDescription(fh:curIdent, event: .readingClosed)
						} else if currentEvent.filter == Int16(EVFILT_WRITE) {
							try? Self.deregister(prim, writer: curIdent)
							let ed = EventDescription(fh:curIdent, event: .writingClosed)
						}
					}
					i = i + 1
				}
				if (i*2 > allocationSize) {
					reallocate(size:allocationSize*2)
				}
			default:
				fatalError("eventtrigger error - this should never happen")
		}
	}
}
#endif

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