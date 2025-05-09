/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

#if os(Linux)
import __cswiftslash_threads
import __cswiftslash_posix_helpers
import __cswiftslash_eventtrigger
import SwiftSlashFIFO
import SwiftSlashPThread
import SwiftSlashFHHelpers
import SwiftSlashFuture
import SwiftSlashGlobalSerialization

internal final class LinuxEventTrigger:EventTriggerEngine {
	internal typealias ArgumentType = EventTriggerSetup<EventTriggerHandle>
	internal typealias ReturnType = Void
	internal typealias EventTriggerHandle = Int32
	internal typealias EventType = epoll_event

	/// the event trigger primitive
	internal let prim:EventTriggerHandlePrimitive

	// the pipe that is used to cancel the event trigger.
	internal let cancelPipe:PosixPipe

	/// the file handle registrations that are currently active.
	private var activeTriggers:[Int32:Register] = [:]
	
	/// the registrations that are pending.
	private let registrations:FIFO<(Int32, Register?), Never>
	private borrowing func extractPendingRegistrations() {
		let getIterator = registrations.makeSyncConsumerNonBlocking()
		infiniteLoop: repeat {
			switch getIterator.next() {
				case .some(let (handle, register)):
					activeTriggers[handle] = register
				case .none:
					break infiniteLoop
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
			let epollResult = epoll_wait(prim, eventBuffer, eventBufferSize, -1)
			switch epollResult {
				// abnormal error conditions.
				case Int32.min..<0:
					switch __cswiftslash_get_errno() {
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
						guard currentEvent.data.fd != cancelPipe.reading else {
							// cancel pipe was triggered, we need to exit the loop.
							continue resultLoop
						}
						if eventFlags & UInt32(EPOLLHUP.rawValue) != 0 {
							// reading handle closed
							// let removedValue = activeTriggers.removeValue(forKey:currentEvent.data.fd)!
							switch activeTriggers[currentEvent.data.fd]! {
								case .reader(_, let future):
									try? future.setSuccess(())
								default:
									fatalError("eventtrigger error - this should never happen. \(#file):\(#line)")
							}

						} else if eventFlags & UInt32(EPOLLERR.rawValue) != 0 {

							// writing handle closed
							// let removedValue = activeTriggers.removeValue(forKey:currentEvent.data.fd)!
							switch activeTriggers[currentEvent.data.fd]! {
								case .writer(_, let future):
									try? future.setSuccess(())
								default:
									fatalError("eventtrigger error - this should never happen. \(#file):\(#line)")
							}

						} else if eventFlags & UInt32(EPOLLIN.rawValue) != 0 {
							
							// read data available
							var byteCount:Int32 = 0
							guard __cswiftslash_fcntl_fionread(currentEvent.data.fd, &byteCount) == 0 else {
								fatalError("fcntl error - this should never happen :: \(#file):\(#line)")
							}
							switch activeTriggers[currentEvent.data.fd]! {
								case .reader(let fifo, _):
									fifo.yield(Int(byteCount))
								default:
									fatalError("eventtrigger error - this should never happen. \(#file):\(#line)")
							}

						} else if eventFlags & UInt32(EPOLLOUT.rawValue) != 0 {
							
							// write data available
							switch activeTriggers[currentEvent.data.fd]! {
								case .writer(let fifo, _):
									fifo.yield(())
								default:
									fatalError("eventtrigger error - this should never happen. \(#file):\(#line)")
							}
							
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

	internal static func newHandlePrimitive() throws(FileHandleError) -> EventTriggerHandle {
		let epCreate = epoll_create1(0)
		guard epCreate != -1 else {
			let errNo = __cswiftslash_get_errno()
			throw FileHandleError.error_unknown(errNo)
		}
		return epCreate
	}

	internal static func closePrimitive(_ prim:consuming EventTriggerHandle) throws(FileHandleError) {
		try prim.closeFileHandle()
	}
}

extension LinuxEventTrigger {
	@SwiftSlashGlobalSerialization internal static func register(_ ev:EventTriggerHandlePrimitive, reader:Int32) throws(EventTriggerErrors) {
		var newEvent = epoll_event()
		newEvent.data.fd = reader
		newEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_ADD, reader, &newEvent) == 0 else {
			throw EventTriggerErrors.readerRegistrationFailure(reader, __cswiftslash_get_errno())
		}
	}

	@SwiftSlashGlobalSerialization internal static func register(_ ev:EventTriggerHandlePrimitive, writer:Int32) throws(EventTriggerErrors) {
		var newEvent = epoll_event()
		newEvent.data.fd = writer
		newEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_ADD, writer, &newEvent) == 0 else {
			throw EventTriggerErrors.writerRegistrationFailure(writer, __cswiftslash_get_errno())
		}
	}

	internal static func deregister(_ ev:EventTriggerHandlePrimitive, reader:Int32) throws(EventTriggerErrors) {
		var buildEvent = epoll_event()
		buildEvent.data.fd = reader
		buildEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_DEL, reader, &buildEvent) == 0 else {
			throw EventTriggerErrors.readerDeregistrationFailure(reader, __cswiftslash_get_errno())
		}
	}

	internal static func deregister(_ ev:EventTriggerHandlePrimitive, writer:Int32) throws(EventTriggerErrors) {
		var buildEvent = epoll_event()
		buildEvent.data.fd = writer
		buildEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_DEL, writer, &buildEvent) == 0 else {
			throw EventTriggerErrors.writerDeregistrationFailure(writer, __cswiftslash_get_errno())
		}
	}
}
#endif