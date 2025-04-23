#if os(Linux)
/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#if os(macOS)
import __cswiftslash_eventtrigger
import SwiftSlashFIFO
import SwiftSlashPThread
import SwiftSlashFHHelpers

internal final class LinuxEventTrigger:EventTriggerEngine {
	internal typealias RuntimeErrors = Never

	internal typealias ArgumentType = EventTriggerSetup<EventTriggerHandle>
	internal typealias ReturnType = Void
	internal typealias EventTriggerHandle = Int32
	internal typealias EventType = kevent

	/// the event trigger primitive
	internal let prim:EventTriggerHandlePrimitive

	// the pipe that is used to cancel the event trigger.
	internal let cancelPipe:PosixPipe

	/// stores the fifo's that read data is passed into.
	private var readersDataOut:[Int32:FIFO<size_t, Never>] = [:]

	/// the fifo that indicates to writing tasks that they can push more data.
	private var writersDataTrigger:[Int32:FIFO<Void, Never>] = [:]
	
	/// the registrations that are pending.
	private let registrations:FIFO<Register, Never>
	private borrowing func extractPendingRegistrations() {
		let getIterator = registrations.makeSyncConsumerNonBlocking()
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
					return
			}
		} while true
	}
	
	internal init(_ ptSetup:consuming ArgumentType) {
		registrations = ptSetup.registersIn
		prim = ptSetup.handle
		cancelPipe = ptSetup.cancelPipe
	}

	/// event buffer that allows us to process events. this buffer is passed directly to the system call and is the first place returned events are stored.
	private var eventBufferSize:Int32 = 32
	private var eventBuffer:UnsafeMutablePointer<EventType> = UnsafeMutablePointer<EventType>.allocate(capacity:32)
	private func reallocate(size:Int32) {
		eventBuffer.deallocate()
		eventBufferSize = size
		eventBuffer = UnsafeMutablePointer<EventType>.allocate(capacity:Int(size))
	}

	deinit {
		eventBuffer.deallocate()
	}

	internal func pthreadWork() throws -> Void {
		// break by pthread cancel
		repeat {

			// wait for events. this might block.
			let epollResult = kevent(prim, nil, 0, eventBuffer, eventBufferSize, nil)
			switch epollResult {
				// abnormal error conditions.
				case Int32.min..<0:
					switch errno {
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
					resultLoop: for i in 0..<Int(kqueueResult) {
						// capture the current event for this iteration
						let currentEvent = eventBuffer[i]
						// capture the file handle that associates with the event.
						let curIdent = Int32(currentEvent.ident)
						// verify that this identifier is not the reading end of the cancel pipe.
						guard curIdent != cancelPipe.reading else {
							// skip the cancel identifier because it does not register with the event trigger so there is nothing to pass on.
							continue resultLoop
						}

						// logic branch to determine if the event is a read or write event, or if it is an EOF event.
						if currentEvent.flags & UInt16(EV_EOF) == 0 {
							if currentEvent.filter == Int16(EVFILT_READ) {
							
								// readable data.
								readersDataOut[curIdent]!.yield(currentEvent.data)

							} else if currentEvent.filter == Int16(EVFILT_WRITE) {

								// writable data.
								writersDataTrigger[curIdent]!.yield(())

							}
						} else {
							if currentEvent.filter == Int16(EVFILT_READ) {

								// reader close.
								readersDataOut.removeValue(forKey:curIdent)!.finish()

							} else if currentEvent.filter == Int16(EVFILT_WRITE) {

								// writer close.
								writersDataTrigger.removeValue(forKey:curIdent)!.finish()
							}
						}
					}

					// reallocate the event buffer if the number of events returned in the latest iteration is encroaching on the buffer size.
					if (kqueueResult*2) > eventBufferSize {
						reallocate(size:eventBufferSize*2)
					}

					// check if the pthread is cancelled.
					pthread_testcancel()
				default:
					fatalError("eventtrigger error - this should never happen")
			}
		} while true
	}

	internal static func newHandlePrimitive() -> EventTriggerHandle {
		return epoll_create1(0)
	}

	internal static func closePrimitive(_ prim:consuming EventTriggerHandle) {
		close(prim)
	}
}

extension MacOSEventTrigger {
	internal static func register(_ ev:EventTriggerHandlePrimitive, reader:Int32) throws(EventTriggerErrors) {
		var newEvent = epoll_event()
		newEvent.data.fd = reader
		newEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_ADD, reader, &newEvent) == 0 else {
			throw RuntimeErrors.readerRegistrationFailure
		}
	}

	internal static func register(_ ev:EventTriggerHandlePrimitive, writer:Int32) throws(EventTriggerErrors) {
		var newEvent = epoll_event()
		newEvent.data.fd = writer
		newEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_ADD, writer, &newEvent) == 0 else {
			throw RuntimeErrors.writerRegistrationFailure
		}
	}

	internal static func deregister(_ ev:EventTriggerHandlePrimitive, reader:Int32) throws(EventTriggerErrors) {
		var buildEvent = epoll_event()
		buildEvent.data.fd = reader
		buildEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_DEL, reader, &buildEvent) == 0 else {
			throw RuntimeErrors.readerDeregistrationFailure
		}
	}

	internal static func deregister(_ ev:EventTriggerHandlePrimitive, writer:Int32) throws(EventTriggerErrors) {
		var buildEvent = epoll_event()
		buildEvent.data.fd = writer
		buildEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_DEL, writer, &buildEvent) == 0 else {
			throw RuntimeErrors.writerDeregistrationFailure
		}
	}
}

/*internal final class LinuxET:EventTriggerEngine {

	internal enum RuntimeErrors:Swift.Error {
		// register
		/// thrown when the reader could not be registered to the event trigger.
		case readerRegistrationFailure
		/// thrown when the writer couuld not be registere to the event trigger.
		case writerRegistrationFailure

		// deregister
		/// thrown when the reader could not be deregistered to the event trigger.
		case readerDeregistrationFailure
		/// thrown when the writer could not be deregistered to the event trigger.
		case writerDeregistrationFailure

		/// thrown when there is a problem with the fcntl call, which is used to determine how many bytes are available to read from the file descriptor.
		case fcntlError
	}

	/// the primitive that is used to handle the event trigger.
	internal typealias Argument = Setup
	/// the primitive that is used to handle the event trigger.
	internal typealias ReturnType = Void
	/// the primitive that is used to handle the event trigger.
	internal typealias EventTriggerHandle = Int32

	internal typealias EventType = epoll_event

	/// the primitive that is used to handle the event trigger.
	internal var prim:EventTriggerHandle = epoll_create1(0)

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
		(prim, registrations) = withUnsafeMutablePointer(to:&ptSetup) { ptsPtr in
			return (ptsPtr.pointee.handle, ptsPtr.pointee.registersIn)
		}
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
			throw RuntimeErrors.readerRegistrationFailure
		}
	}

	internal static func register(_ ev:EventTriggerHandle, writer:Int32) throws {
		var newEvent = epoll_event()
		newEvent.data.fd = writer
		newEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_ADD, writer, &newEvent) == 0 else {
			throw RuntimeErrors.writerRegistrationFailure
		}
	}

	internal static func deregister(_ ev:EventTriggerHandle, reader:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = reader
		buildEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_DEL, reader, &buildEvent) == 0 else {
			throw RuntimeErrors.readerDeregistrationFailure
		}
	}

	internal static func deregister(_ ev:EventTriggerHandle, writer:Int32) throws {
		var buildEvent = epoll_event()
		buildEvent.data.fd = writer
		buildEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_DEL, writer, &buildEvent) == 0 else {
			throw RuntimeErrors.writerDeregistrationFailure
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
							readersDataOut.removeValue(forKey:currentEvent.data.fd)!.finish()

						} else if eventFlags & UInt32(EPOLLERR.rawValue) != 0 {

							// writing handle closed
							writersDataTrigger.removeValue(forKey:currentEvent.data.fd)!.finish()

						} else if eventFlags & UInt32(EPOLLIN.rawValue) != 0 {
							
							// read data available
							var byteCount:Int32 = 0
							guard _cswiftslash_fcntl_fionread(currentEvent.data.fd, &byteCount) == 0 else {
								throw RuntimeErrors.fcntlError
							}
							
							readersDataOut[currentEvent.data.fd]!.yield(Int(currentEvent.data.fd))
						} else if eventFlags & UInt32(EPOLLOUT.rawValue) != 0 {
							
							// write data available
							writersDataTrigger[currentEvent.data.fd]!.yield(())
							
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
}*/
#endif