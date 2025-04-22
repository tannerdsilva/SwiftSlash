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

internal final class MacOSEventTrigger:EventTriggerEngine {
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
			let kqueueResult = kevent(prim, nil, 0, eventBuffer, eventBufferSize, nil)

			switch kqueueResult {
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
		return kqueue()
	}

	internal static func closePrimitive(_ prim:consuming EventTriggerHandle) {
		close(prim)
	}
}

extension MacOSEventTrigger {
	internal static func register(_ ev:EventTriggerHandlePrimitive, reader:Int32) throws(EventTriggerErrors) {
		var newEvent = kevent()
		newEvent.ident = UInt(reader)
		newEvent.flags = UInt16(EV_ADD | EV_CLEAR | EV_EOF)
		newEvent.filter = Int16(EVFILT_READ)
		newEvent.fflags = 0
		newEvent.data = 0
		newEvent.udata = nil
		guard kevent(ev, &newEvent, 1, nil, 0, nil) == 0 else {
			throw EventTriggerErrors.readerRegistrationFailure(reader, errno)
		}
	}

	internal static func register(_ ev:EventTriggerHandlePrimitive, writer:Int32) throws(EventTriggerErrors) {
		var newEvent = kevent()
		newEvent.ident = UInt(writer)
		newEvent.flags = UInt16(EV_ADD | EV_CLEAR | EV_EOF)
		newEvent.filter = Int16(EVFILT_WRITE)
		newEvent.fflags = 0
		newEvent.data = 0
		newEvent.udata = nil
		guard kevent(ev, &newEvent, 1, nil, 0, nil) == 0 else {
			throw EventTriggerErrors.writerRegistrationFailure(writer, errno)
		}
	}

	internal static func deregister(_ ev:EventTriggerHandlePrimitive, reader:Int32) throws(EventTriggerErrors) {
		var newEvent = kevent()
		newEvent.ident = UInt(reader)
		newEvent.flags = UInt16(EV_DELETE | EV_CLEAR | EV_EOF)
		newEvent.filter = Int16(EVFILT_READ)
		newEvent.fflags = 0
		newEvent.data = 0
		newEvent.udata = nil
		guard kevent(ev, &newEvent, 1, nil, 0, nil) == 0 else {
			throw EventTriggerErrors.readerDeregistrationFailure(reader, errno)
		}
	}

	internal static func deregister(_ ev:EventTriggerHandlePrimitive, writer:Int32) throws(EventTriggerErrors) {
		var newEvent = kevent()
		newEvent.ident = UInt(writer)
		newEvent.flags = UInt16(EV_DELETE | EV_CLEAR | EV_EOF)
		newEvent.filter = Int16(EVFILT_WRITE)
		newEvent.fflags = 0
		newEvent.data = 0
		newEvent.udata = nil
		guard kevent(ev, &newEvent, 1, nil, 0, nil) == 0 else {
			throw EventTriggerErrors.writerDeregistrationFailure(writer, errno)
		}
	}
}
#endif