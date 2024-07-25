#if os(Linux)
import __cswiftslash
import SwiftSlashFIFO
import SwiftSlashPThread

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

	internal func eventTriggerWork() throws {
		let epollET = epoll_wait(epoll, epollEventsAllocation, allocationSize, -1) 
	}

	deinit {
		close(prim)
		events.deallocate()	// no need to deinitialize since the Pointee type is a c struct.
	}
}
#endif