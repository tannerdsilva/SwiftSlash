#if os(Linux)
import __cswiftslash
import SwiftSlashFIFO
import SwiftSlashPThread

internal final class LinuxET {

	/// the primitive that is used to handle the event trigger.
	internal typealias Argument = Setup
	/// the primitive that is used to handle the event trigger.
	internal typealias ReturnType = Void
	/// the primitive that is used to handle the event trigger.
	internal typealias EventTriggerHandle = Int32

	internal typealias EventType = epoll_event

	/// the primitive that is used to handle the event trigger.
	private var prim:EventTriggerHandle = epoll_create1(0)

	/// stores the fifo's that read data is passed into.
	private var readersDataOut:[Int32:FIFO<size_t, Swift.Error>] = [:]

	/// the fifo that indicates to writing tasks that they can push more data.
	private var writersDataTrigger:[Int32:FIFO<Void, Swift.Error>] = [:]
	
	/// the registrations that are pending.
	private let registrations:FIFO<Register, Never>
	private func extractPendingRegistrations() {
		let getIterator = registrations.makeSyncConsumer(shouldBlock:false)
		infiniteLoop: repeat {
			switch getIterator.next() {
				case .some(let reg):
					switch reg {
						case .reader(let i, let f):
							readersDataOut[i] = f
						case .writer(let i, let f):
							writersDataTrigger[i] = f
					}
				case .none:
					break infiniteLoop
			}
		} while true
	}
	
	internal init(_ ptSetup:consuming Argument) {
		registrations = ptSetup.registersIn
		prim = ptSetup.handle
	}

	/// event buffer that allows us to process events. this buffer is passed directly to the system call and is the first place returned events are stored.
	private var eventBufferSize:Int32 = 32
	private var eventBuffer:UnsafeMutablePointer<EventType> = UnsafeMutablePointer<EventType>.allocate(capacity:32)	// no need to initialize this since the Pointee type is a c struct.
	private func reallocate(size:Int32) {
		eventBuffer.deallocate()
		eventBufferSize = size
		eventBuffer = UnsafeMutablePointer<EventType>.allocate(capacity:Int(size))
	}

	deinit {
		close(prim)
		eventBuffer.deallocate()	// no need to deinitialize since the Pointee type is a c struct.
	}

	internal static func register(_ ev:EventTriggerHandle, reader:Int32) throws {
		var newEvent = epoll_event()
		newEvent.data.fd = reader
		newEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_ADD, reader, &newEvent) == 0 else {
			throw Error.unableToRegister
		}
	}

	internal static func register(_ ev:EventTriggerHandle, writer:Int32) throws {
		var newEvent = epoll_event()
		newEvent.data.fd = writer
		newEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_ADD, writer, &newEvent) == 0 else {
			throw Error.unableToRegister
		}
	}

	internal static func deregister(_ ev:EventTriggerHandle, reader:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = reader
		buildEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_DEL, reader, &buildEvent) == 0 else {
			throw Error.unableToRegister
		}
	}

	internal static func deregister(_ ev:EventTriggerHandle, writer:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = writer
		buildEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_DEL, writer, &buildEvent) == 0 else {
			throw Error.unableToRegister
		}
	}

	internal func pthreadWork() throws -> Void {
		// build the signal set that can be used to break the epoll_pwait.
		// in this case, we only want epoll_pwait to be broken by SIGUSR1.
		var sigset = sigset_t()
		sigemptyset(&sigset)
		sigaddset(&sigset, SIGUSR1)

		// break by pthread cancel only.
		repeat {

			// wait for events
			let epollResult = epoll_pwait(prim, eventBuffer, eventBufferSize, -1, &sigset)

			switch epollResult {
				// abnormal error conditions.
				case Int32.min..<0:
					
					switch _cswiftslash_get_errno() {
						case EINTR:
							pthread_testcancel()
						default:
							fatalError("kevent error - this should never happen")
					}
				
				// any zero or positive value is considered a normal condition.
				case 0..<Int32.max:
				
					// acquire any w/r fifo's that were passed into the registration queue while this thread was blocked.
					extractPendingRegistrations()
					
					// process the events against the stored fifo's.
					resultLoop: for i in 0..<Int(epollResult) {

						// capture the relevant two points for this iteration: file handle and the flags triggered for said handle.
						let currentEvent = eventBuffer[i]
						let eventFlags = currentEvent.events
						
						if eventFlags & UInt32(EPOLLHUP.rawValue) != 0 {
							// reading handle closed
						} else if eventFlags & UInt32(EPOLLERR.rawValue) != 0 {
							// writing handle closed
						} else if eventFlags & UInt32(EPOLLIN.rawValue) != 0 {
							// read data available
							var byteCount:Int32 = 0
							guard _cswiftslash_fcntl_fionread(currentEvent.data.fd, &byteCount) == 0 else {
								return 
							}
							readersDataOut[currentEvent.data.fd]!.yield(Int(currentEvent.data.fd))
						} else if eventFlags & UInt32(EPOLLOUT.rawValue) != 0 {
							// write data available
						}
					}

					// reallocate the event buffer if the event is getting too large.
					if epollResult*2 > eventBufferSize {
						reallocate(size:eventBufferSize*2)
					}

					// check if the pthread is cancelled.
					pthread_testcancel()
				default:
					fatalError("eventtrigger error - this should never happen")
			}
		} while true
	}

	internal static func newPrimitive() -> EventTriggerHandle {
		return epoll_create1(0)
	}

	internal static func closePrimitive(_ prim:EventTriggerHandle) {
		close(prim)
	}
}
#endif