import ClibSwiftSlash
import Foundation

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

#if os(Linux)
internal struct EventTrigger {
	internal static func launchNew() -> EventTrigger {
		let newET = EventTrigger()
		DispatchQueue(label:"com.swiftslash.event-trigger").async {
			newET._mainLoop()
		}
		return newET
	}
	enum Error:Swift.Error {
		case unableToRegister
	}
	
	fileprivate let epoll = epoll_create1(0);
	
	internal let eventStream:AsyncStream<EventDescription>
	
	fileprivate let eventContinuation:AsyncStream<EventDescription>.Continuation
	
	fileprivate init() {
		var eventCont:AsyncStream<EventDescription>.Continuation? = nil
		self.eventStream = AsyncStream<EventDescription> { cont in
			eventCont = cont
		}
		self.eventContinuation = eventCont!
	}
	
	fileprivate func _mainLoop() {
		var epollEventsAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:32)
		var allocationSize:Int32 = 32
		func reallocate(size:Int32) {
			epollEventsAllocation.deallocate()
			epollEventsAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:Int(size))
			allocationSize = size
		}
		
		while true {
			let pollResult = epoll_wait(epoll, epollEventsAllocation, allocationSize, -1) 
			switch pollResult {
				case -1:
					fatalError("EPOLL ERROR")
					break;
				default:
					if (pollResult > 0) {
						var i = 0
						while (i < pollResult) {
							let currentEvent = epollEventsAllocation[i]
							let pollin = currentEvent.events & UInt32(EPOLLIN.rawValue)
							let pollhup = currentEvent.events & UInt32(EPOLLHUP.rawValue)
							let pollout = currentEvent.events & UInt32(EPOLLOUT.rawValue)
							let pollerr = currentEvent.events & UInt32(EPOLLERR.rawValue)
							
							if (pollhup != 0) {
								//reading handle closed
								try? self.deregister(reader:currentEvent.data.fd)
								self.eventContinuation.yield((EventDescription(fh:currentEvent.data.fd, event:.readingClosed)))
							} else if (pollerr != 0) {
								//writing handle closed
								try? self.deregister(writer:currentEvent.data.fd)
								self.eventContinuation.yield((EventDescription(fh:currentEvent.data.fd, event:.writingClosed)))
							} else if (pollin != 0) {
								//read data available
								var byteCount:Int = 0
								guard ioctl(currentEvent.data.fd, UInt(FIONREAD), &byteCount) == 0 else {
									fatalError("EventTrigger ioctl error")
								}
								self.eventContinuation.yield((EventDescription(fh:currentEvent.data.fd, event:.readableEvent(byteCount))))
							} else if (pollout != 0) {
								//writing available
								self.eventContinuation.yield((EventDescription(fh:currentEvent.data.fd, event:.writableEvent)))
							}
							i = i + 1
						}
						if (i*2 > allocationSize) {
							reallocate(size:allocationSize*2)
						}
					}
			}
		}
	}
	
	func register(reader:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = reader
		buildEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(self.epoll, EPOLL_CTL_ADD, reader, &buildEvent) == 0 else {
			throw Error.unableToRegister
		}
	}
	
	func register(writer:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = writer
		buildEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(self.epoll, EPOLL_CTL_ADD, writer, &buildEvent) == 0 else {
			throw Error.unableToRegister
		}
	}
	
	func deregister(reader:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = reader
		buildEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(self.epoll, EPOLL_CTL_DEL, reader, &buildEvent) == 0 else {
			throw Error.unableToRegister
		}
	}
	
	func deregister(writer:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = writer
		buildEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(self.epoll, EPOLL_CTL_DEL, writer, &buildEvent) == 0 else {
			throw Error.unableToRegister
		}
	}
}
#elseif os(macOS)
import Darwin

internal struct EventTrigger {
    internal static func launchNew() -> Self {
        let newET = EventTrigger()
        let mainLoopQueue = DispatchQueue(label:"com.swiftslash.event-trigger")
        mainLoopQueue.async {
            newET._mainLoop()
        }
        return newET
    }
    enum Error:Swift.Error {
        case unableToRegister
    }

    fileprivate let queue = kqueue()
    
    internal let eventStream:AsyncStream<EventDescription>
    
    fileprivate let eventContinuation:AsyncStream<EventDescription>.Continuation
    
    fileprivate init() {
        var eventCont:AsyncStream<EventDescription>.Continuation? = nil
        self.eventStream = AsyncStream<EventDescription> { cont in
            eventCont = cont
        }
        self.eventContinuation = eventCont!
    }
    
    fileprivate func _mainLoop() {
        var kqueueEventsAllocation = UnsafeMutablePointer<kevent>.allocate(capacity:32)
        var allocationSize:Int32 = 32
        func reallocate(size:Int32) {
            kqueueEventsAllocation.deallocate()
            kqueueEventsAllocation = UnsafeMutablePointer<kevent>.allocate(capacity:Int(size))
            allocationSize = size
        }
        while true {
            let kqueueResult = kevent(self.queue, nil, 0, kqueueEventsAllocation, allocationSize, nil)
            switch kqueueResult {
                case -1:
                    print("KQUEUE ERROR")
                    break;
                default:
                    if kqueueResult > 0 {
                        var i = 0
                        while (i < kqueueResult) {
                            let currentEvent = kqueueEventsAllocation[i]
                            let kqueueClosed = currentEvent.flags & UInt16(EV_EOF)
                            let kqueueIn = currentEvent.filter & Int16(EVFILT_READ)
                            let kqueueOut = currentEvent.filter & Int16(EVFILT_WRITE)
                            let curIdent = Int32(currentEvent.ident)
                            if kqueueClosed == 0 {
                                if currentEvent.filter == Int16(EVFILT_READ) {
                                    self.eventContinuation.yield(EventDescription(fh:curIdent, event: .readableEvent(currentEvent.data)))
                                } else if currentEvent.filter == Int16(EVFILT_WRITE) {
                                    self.eventContinuation.yield(EventDescription(fh:curIdent, event: .writableEvent))
                                }
                            } else {
                                if currentEvent.filter == Int16(EVFILT_READ) {
                                    try? self.deregister(reader: curIdent)
                                    self.eventContinuation.yield(EventDescription(fh:curIdent, event: .readingClosed))
                                } else if currentEvent.filter == Int16(EVFILT_WRITE) {
                                    try? self.deregister(writer: curIdent)
                                    self.eventContinuation.yield(EventDescription(fh:curIdent, event: .writingClosed))
                                }
                            }
                            i = i + 1
                        }
                        if (i*2 > allocationSize) {
                            reallocate(size:allocationSize*2)
                        }
                    }
            }
        }
    }
    
    func register(reader:Int32) throws {
        var newEvent = kevent()
        newEvent.ident = UInt(reader)
        newEvent.flags = UInt16(EV_ADD | EV_CLEAR | EV_EOF)
        newEvent.filter = Int16(EVFILT_READ)
        newEvent.fflags = 0
        newEvent.data = 0
        newEvent.udata = nil
        guard kevent(queue, &newEvent, 1, nil, 0, nil) == 0 else {
            throw Error.unableToRegister
        }
    }
    
    func register(writer:Int32) throws {
        var newEvent = kevent()
        newEvent.ident = UInt(writer)
        newEvent.flags = UInt16(EV_ADD | EV_CLEAR | EV_EOF)
        newEvent.filter = Int16(EVFILT_WRITE)
        newEvent.fflags = 0
        newEvent.data = 0
        newEvent.udata = nil
        guard kevent(queue, &newEvent, 1, nil, 0, nil) == 0 else {
            throw Error.unableToRegister
        }
    }
    
    func deregister(reader:Int32) throws {
        var newEvent = kevent()
        newEvent.ident = UInt(reader)
        newEvent.flags = UInt16(EV_DELETE | EV_CLEAR | EV_EOF)
        newEvent.filter = Int16(EVFILT_READ)
        newEvent.fflags = 0
        newEvent.data = 0
        newEvent.udata = nil
        guard kevent(queue, &newEvent, 1, nil, 0, nil) == 0 else {
            throw Error.unableToRegister
        }
    }
    
    func deregister(writer:Int32) throws {
        var newEvent = kevent()
        newEvent.ident = UInt(writer)
        newEvent.flags = UInt16(EV_DELETE | EV_CLEAR | EV_EOF)
        newEvent.filter = Int16(EVFILT_WRITE)
        newEvent.fflags = 0
        newEvent.data = 0
        newEvent.udata = nil
        guard kevent(queue, &newEvent, 1, nil, 0, nil) == 0 else {
            throw Error.unableToRegister
        }
    }
}
#endif
