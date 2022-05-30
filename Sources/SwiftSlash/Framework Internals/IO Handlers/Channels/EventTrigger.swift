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
internal actor EventTrigger {
	static func launchNew() -> EventTrigger {
		let newET = Self()
		Task.detached {
			await newET._mainLoop()
		}
		return newET
	}

	enum Error:Swift.Error {
		case unableToRegister
		case mainLoopAlreadyLaunched
	}

	fileprivate var epoll:Int32 = epoll_create1(0)
	
	internal let eventStream:AsyncStream<EventDescription>
	fileprivate let eventContinuation:AsyncStream<EventDescription>.Continuation
	
	fileprivate var loopRunning:Bool = false
	
	fileprivate init() {
		var eventCont:AsyncStream<EventDescription>.Continuation? = nil
		self.eventStream = AsyncStream<EventDescription> { cont in
			eventCont = cont
		}
		self.eventContinuation = eventCont!
	}
	
	fileprivate func launchMainLoop() {
		self.loopRunning = true
	}
	fileprivate func closeMainLoop() {
		self.loopRunning = false
	}
	
	nonisolated fileprivate func _mainLoop() async {
		await self.launchMainLoop()
	
		// buffer for epoll event structures
		var epollEventsAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:32)
		
		// for resizing the epoll event buffer if it needs to accomodate more file descriptors
		var allocationSize:Int32 = 32
		func reallocate(size:Int32) {
			epollEventsAllocation.deallocate()
			epollEventsAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:Int(size))
			allocationSize = size
		}

		while Task.isCancelled == false {
			let pollResult = await withUnsafeContinuation({ [ep = await self.epoll] (eventCont:UnsafeContinuation<Int32, Never>) in
				eventCont.resume(returning:epoll_wait(ep, epollEventsAllocation, allocationSize, -1))
			})
			switch pollResult {
				case -1:
					let errnum = errno
					switch errnum {
					case EINTR:
						print("EPOLL ERROR EINTR")
					case EBADF:
						print("EPOLL ERROR EBADF")
					case EFAULT:
						print("EPOLL ERROR EFAULT")
					case EINVAL:
						print("EPOLL ERRNO EINVAL")
					default:
						print("EPOLL ERRNO \(errnum)")
					}
				default:
					if pollResult > 0 {
						var i = 0
						var closeReaders = Set<Int32>()
						var closeWriters = Set<Int32>()
						while i < pollResult {
							let currentEvent = epollEventsAllocation[i]
							let pollin = currentEvent.events & UInt32(EPOLLIN.rawValue)
							let pollhup = currentEvent.events & UInt32(EPOLLHUP.rawValue)
							let pollout = currentEvent.events & UInt32(EPOLLOUT.rawValue)
							let pollerr = currentEvent.events & UInt32(EPOLLERR.rawValue)
						
							if (pollhup != 0) {
								//reading handle closed
								closeReaders.update(with:currentEvent.data.fd)
							} else if (pollerr != 0) {
								//writing handle closed
								closeWriters.update(with:currentEvent.data.fd)
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
						if (closeWriters.count + closeReaders.count > 0) {
							try! await self.deregister(readers:closeReaders, writers:closeWriters)
							for closeReader in closeReaders {
								self.eventContinuation.yield(EventDescription(fh:closeReader, event:.readingClosed))
							}
							for closeWriter in closeWriters {
								self.eventContinuation.yield(EventDescription(fh:closeWriter, event:.writingClosed))
							}
						}
					}
					
			}
		}
		await self.closeMainLoop()
	}
	
	fileprivate func register(reader:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = reader
		buildEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(self.epoll, EPOLL_CTL_ADD, reader, &buildEvent) == 0 else {
			throw Error.unableToRegister
		}
	}
	
	fileprivate func register(writer:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = writer
		buildEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(self.epoll, EPOLL_CTL_ADD, writer, &buildEvent) == 0 else {
			throw Error.unableToRegister
		}
	}
	
	fileprivate func deregister(reader:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = reader
		buildEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(self.epoll, EPOLL_CTL_DEL, reader, &buildEvent) == 0 else {
			throw Error.unableToRegister
		}
	}
	
	fileprivate func deregister(writer:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = writer
		buildEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(self.epoll, EPOLL_CTL_DEL, writer, &buildEvent) == 0 else {
			throw Error.unableToRegister
		}
	}
	
	internal func register(readers:Set<Int32>, writers:Set<Int32>) throws {
		var readersToDeregisterIfThrown = Set<Int32>()
		var writersToDeregisterIfThrown = Set<Int32>()
		do {
			for reader in readers {
				try self.register(reader:reader)
				readersToDeregisterIfThrown.update(with:reader)
			}
			for writer in writers {
				try self.register(writer:writer)
				writersToDeregisterIfThrown.update(with:writer)
			}
		} catch let error {
			for readerToDeregister in readersToDeregisterIfThrown {
				try self.deregister(reader:readerToDeregister)
			}
			for writerToDeregister in writersToDeregisterIfThrown {
				try self.deregister(writer:writerToDeregister)
			}
			throw error
		}
	}
	
	internal func deregister(readers:Set<Int32>, writers:Set<Int32>) throws {
		for reader in readers {
			try self.deregister(reader:reader)
		}
		for writer in writers {
			try self.deregister(writer:writer)
		}
	}
}
/*internal struct EventTrigger {
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
					if (errno != EINTR) {
						fatalError("EPOLL ERROR \(errno)")
					}
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
}*/
#elseif os(macOS)
import Darwin
internal actor EventTrigger {
	static func launchNew() -> EventTrigger {
		let newET = Self()
		Task.detached {
			await newET._mainLoop()
		}
		return newET
	}

	enum Error:Swift.Error {
		case unableToRegister
		case mainLoopAlreadyLaunched
	}

	fileprivate var queue:Int32 = kqueue()
	
	internal let eventStream:AsyncStream<EventDescription>
	fileprivate let eventContinuation:AsyncStream<EventDescription>.Continuation
	
	fileprivate var loopRunning:Bool = false
	
	fileprivate init() {
		var eventCont:AsyncStream<EventDescription>.Continuation? = nil
		self.eventStream = AsyncStream<EventDescription> { cont in
			eventCont = cont
		}
		self.eventContinuation = eventCont!
	}
	
	fileprivate func launchMainLoop() {
		self.loopRunning = true
	}
	fileprivate func closeMainLoop() {
		self.loopRunning = false
	}
	
	nonisolated fileprivate func _mainLoop() async {
		await self.launchMainLoop()
		var kqueueEventsAllocation = UnsafeMutablePointer<kevent>.allocate(capacity:32)
		var allocationSize:Int32 = 32
		func reallocate(size:Int32) {
			kqueueEventsAllocation.deallocate()
			kqueueEventsAllocation = UnsafeMutablePointer<kevent>.allocate(capacity:Int(size))
			allocationSize = size
		}
		while Task.isCancelled == false {
			let kqueueResult = await withUnsafeContinuation({ [queue = await self.queue] (eventCont:UnsafeContinuation<Int32, Never>) in
				eventCont.resume(returning:kevent(queue, nil, 0, kqueueEventsAllocation, allocationSize, nil))
			})
			switch kqueueResult {
				case -1:
					let errnum = errno
					switch errnum {
					case EINTR:
						print("KQUEUE ERROR EINTR")
					case EBADF:
						print("KQUEUE ERROR EBADF")
					case EFAULT:
						print("KQUEUE ERROR EFAULT")
					case EINVAL:
						print("KQUEUE ERRNO EINVAL")
					default:
						print("KQUEUE ERRNO \(errnum)")
					}
					break;
				default:
					if kqueueResult > 0 {
						var i = 0
						var closeReaders = Set<Int32>()
						var closeWriters = Set<Int32>()
						while (i < kqueueResult) {
							let currentEvent = kqueueEventsAllocation[i]
							let kqueueClosed = currentEvent.flags & UInt16(EV_EOF)

							let curIdent = Int32(currentEvent.ident)
							if kqueueClosed == 0 {
								if currentEvent.filter == Int16(EVFILT_READ) {
									self.eventContinuation.yield(EventDescription(fh:curIdent, event: .readableEvent(currentEvent.data)))
								} else if currentEvent.filter == Int16(EVFILT_WRITE) {
									self.eventContinuation.yield(EventDescription(fh:curIdent, event: .writableEvent))
								}
							} else {
								if currentEvent.filter == Int16(EVFILT_READ) {
									closeReaders.update(with: curIdent)
								} else if currentEvent.filter == Int16(EVFILT_WRITE) {
									closeWriters.update(with: curIdent)
								}
							}
							i = i + 1
						}
						if (i*2 > allocationSize) {
							reallocate(size:allocationSize*2)
						}
						if (closeWriters.count + closeReaders.count > 0) {
							try! await self.deregister(readers: closeReaders, writers: closeWriters)
							for closeReader in closeReaders {
								self.eventContinuation.yield(EventDescription(fh:closeReader, event:.readingClosed))
							}
							for closeWriter in closeWriters {
								self.eventContinuation.yield(EventDescription(fh:closeWriter, event:.writingClosed))
							}
						}
					}
			}
		}
		await self.closeMainLoop()
	}
	
	fileprivate func register(reader:Int32) throws {
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
	
	fileprivate func register(writer:Int32) throws {
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
	
	fileprivate func deregister(reader:Int32) throws {
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
	
	fileprivate func deregister(writer:Int32) throws {
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
	
	internal func register(readers:Set<Int32>, writers:Set<Int32>) throws {
		var readersToDeregisterIfThrown = Set<Int32>()
		var writersToDeregisterIfThrown = Set<Int32>()
		do {
			for reader in readers {
				try self.register(reader:reader)
				readersToDeregisterIfThrown.update(with:reader)
			}
			for writer in writers {
				try self.register(writer:writer)
				writersToDeregisterIfThrown.update(with:writer)
			}
		} catch let error {
			for readerToDeregister in readersToDeregisterIfThrown {
				try self.deregister(reader:readerToDeregister)
			}
			for writerToDeregister in writersToDeregisterIfThrown {
				try self.deregister(writer:writerToDeregister)
			}
			throw error
		}
	}
	
	internal func deregister(readers:Set<Int32>, writers:Set<Int32>) throws {
		for reader in readers {
			try self.deregister(reader:reader)
		}
		for writer in writers {
			try self.deregister(writer:writer)
		}
	}

}
/*internal struct EventTrigger {
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
                    if (errno != EINTR) {
                        fatalError("KQUEUE ERROR")
                    }
                    break;
                default:
                    if kqueueResult > 0 {
                        var i = 0
                        while (i < kqueueResult) {
                            let currentEvent = kqueueEventsAllocation[i]
                            let kqueueClosed = currentEvent.flags & UInt16(EV_EOF)

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
*/
#endif
