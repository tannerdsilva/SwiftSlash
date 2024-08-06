#if os(macOS)
import __cswiftslash
import SwiftSlashFIFO
import SwiftSlashPThread

internal final class MacOSImpl:EventTriggerEngine {
	
	internal typealias Argument = Setup
	internal typealias ReturnType = Void
	internal typealias EventTriggerHandle = Int32
	internal typealias EventType = kevent

	/// the event trigger primitive
	internal let prim:EventTriggerHandle

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

	internal static func register(_ ev:EventTriggerHandle, writer:Int32) throws {
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

	internal static func deregister(_ ev:EventTriggerHandle, reader:Int32) throws {
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

	internal static func deregister(_ ev:EventTriggerHandle, writer:Int32) throws {
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

	internal func pthreadWork() throws -> Void {
		// break by pthread cancel
		repeat {

			// wait for events
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
						let currentEvent = eventBuffer[i]
						let curIdent = Int32(currentEvent.ident)
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

					// reallocate the event buffer if the event is getting too large.
					if kqueueResult*2 > eventBufferSize {
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
		return kqueue()
	}

	internal static func closePrimitive(_ prim:EventTriggerHandle) {
		close(prim)
	}
}
#endif