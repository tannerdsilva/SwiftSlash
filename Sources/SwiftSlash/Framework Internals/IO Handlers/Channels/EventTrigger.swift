import Cepoll
import Foundation

internal enum EventMode {
	case readableEvent
	case writableEvent
	case readingClosed
	case writingClosed
}

internal struct EventTrigger {
	internal static func launchNew(_ handler:@escaping((Int32, EventMode) -> Void)) -> Self {
		let newET = EventTrigger(handler)
		let mainLoopQueue = DispatchQueue(label:"com.swiftslash.event-trigger")
		mainLoopQueue.async {
			newET._mainLoop()
		}
		return newET
	}
	enum Error:Swift.Error {
		case unableToRegister
	}
	
	fileprivate let epoll = epoll_create1(0);
	
	fileprivate let handler:(Int32, EventMode) -> Void
	
	fileprivate init(_ handler:@escaping((Int32, EventMode) -> Void)) {
		self.handler = handler
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
					print("EPOLL ERROR")
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
								self.handler(currentEvent.data.fd, .readingClosed)
							} else if (pollerr != 0) {
								//writing handle closed
								self.handler(currentEvent.data.fd, .writingClosed)
							} else if (pollin != 0) {
								//read data available
								self.handler(currentEvent.data.fd, .readableEvent)
							} else if (pollout != 0) {
								//writing available
								self.handler(currentEvent.data.fd, .writableEvent)
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
