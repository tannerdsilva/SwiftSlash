/*
LICENSE MIT
copyright (c) tanner silva 2026. all rights reserved.

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

/// the primary event trigger implementation for linux.
/// 	- NOTE: this class is marked with `unchecked Sendable` because it has mutable storage for `activeTriggers`. As required by the Swift runtime, the access to this mutable storage is perfectly isolated and managed to only a single thread.
internal final class LinuxEventTrigger:EventTriggerEngine, @unchecked Sendable {
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

	/// process exit monitors, keyed by pid. held separately from the fd-keyed
	/// `activeTriggers` dictionary so a pid number can never collide with an open file
	/// descriptor in the parent process. pid-keyed epoll events are additionally
	/// namespaced by `processEventMarker` in the data union.
	private var processMonitors:[Int32: FIFO<Int, Never>] = [:]

	/// the high bit of the epoll data union that marks a process-exit (pidfd) event.
	fileprivate static let processEventMarker:UInt64 = UInt64(1) << 63

	/// the pidfds that are currently registered for process exit monitoring, keyed by the monitored pid.
	/// only mutated from `register(process:)`/`deregister(process:)`, which are globally serialized.
	@SwiftSlashGlobalSerialization fileprivate static var activeProcessPidfds:[Int32:Int32] = [:]
	
	/// the registrations that are pending.
	private let registrations:FIFO<(Int32, Register?), Never>
	private borrowing func extractPendingRegistrations() {
		let getIterator = registrations.makeSyncConsumerNonBlocking()
		infiniteLoop: repeat {
			switch getIterator.next() {
				case .some(let (handle, register)):
					switch register {
						case .some(let r):
							switch r {
								case .process(let fifo):
									processMonitors[handle] = fifo
								default:
									activeTriggers[handle] = r
							}
						case .none:
							activeTriggers.removeValue(forKey:handle)
							// the removed key may have been a process monitor; clear it too.
							processMonitors.removeValue(forKey:handle)
					}
				case .none:
					break infiniteLoop
			}
		} while true
	}
	
	internal init(_ ptSetup:sending ArgumentType) {
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

	internal func pthreadWork() throws -> sending Void {
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
						if currentEvent.data.u64 & LinuxEventTrigger.processEventMarker != 0 {
							// a monitored process has exited (a pidfd event). pid-keyed events are
							// namespaced away from fd-keyed events, even when the pid numerically
							// collides with an open file descriptor.
							let processPid = Int32(bitPattern:UInt32(truncatingIfNeeded:currentEvent.data.u64 & ~LinuxEventTrigger.processEventMarker))
							processMonitors[processPid]?.yield(1)
							continue resultLoop
						}
						guard currentEvent.data.fd != cancelPipe.reading else {
							// cancel pipe was triggered, we need to exit the loop.
							continue resultLoop
						}
						if eventFlags & UInt32(EPOLLHUP.rawValue) != 0 {
							// reading handle closed, or a monitored process has exited (pidfd HUP).
							// let removedValue = activeTriggers.removeValue(forKey:currentEvent.data.fd)!
							switch activeTriggers[currentEvent.data.fd] {
								case .some(.reader(_, let future)):
									_ = try? future.setSuccess(())
								case .none:
									// a deregistration raced with an in-flight event; nothing to do.
									break
								default:
									fatalError("eventtrigger error - this should never happen. \(#file):\(#line)")
							}

						} else if eventFlags & UInt32(EPOLLERR.rawValue) != 0 {

							// writing handle closed
							// let removedValue = activeTriggers.removeValue(forKey:currentEvent.data.fd)!
							switch activeTriggers[currentEvent.data.fd] {
								case .some(.writer(_, let future)):
									_ = try? future.setSuccess(())
								case .none:
									// a deregistration raced with an in-flight event; nothing to do.
									break
								default:
									fatalError("eventtrigger error - this should never happen. \(#file):\(#line)")
							}

						} else if eventFlags & UInt32(EPOLLIN.rawValue) != 0 {

							// read data available, or a monitored process (via its pidfd) has exited.
							switch activeTriggers[currentEvent.data.fd] {
								case .some(.reader(let fifo, _)):
									var byteCount:Int32 = 0
									guard __cswiftslash_fcntl_fionread(currentEvent.data.fd, &byteCount) == 0 else {
										fatalError("fcntl error - this should never happen :: \(#file):\(#line)")
									}
									fifo.yield(Int(byteCount))
								case .none:
									// a deregistration raced with an in-flight event; nothing to do.
									break
								default:
									fatalError("eventtrigger error - this should never happen. \(#file):\(#line)")
							}

						} else if eventFlags & UInt32(EPOLLOUT.rawValue) != 0 {
							
							// write data available
							switch activeTriggers[currentEvent.data.fd] {
								case .some(.writer(let fifo, _)):
									fifo.yield(())
								case .none:
									// a deregistration raced with an in-flight event; nothing to do.
									break
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

	@SwiftSlashGlobalSerialization internal static func register(_ ev:EventTriggerHandlePrimitive, process pid:Int32) throws(EventTriggerErrors) {
		// a pidfd becomes pollable (EPOLLIN) when the monitored process has exited.
		// this registration keys the event payload by the pid (not the pidfd) so the
		// dispatch loop and the registration stream stay symmetric with macOS.
		let pidfd = __cswiftslash_pidfd_open(pid)
		guard pidfd != -1 else {
			throw EventTriggerErrors.processRegistrationFailure(pid, __cswiftslash_get_errno())
		}
		var newEvent = epoll_event()
		// namespace the registration with the high-bit marker so a pid that numerically
		// equals an open parent file descriptor can never be confused with an fd event.
		newEvent.data.u64 = processEventMarker | UInt64(UInt32(bitPattern:pid))
		newEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		guard epoll_ctl(ev, EPOLL_CTL_ADD, pidfd, &newEvent) == 0 else {
			let errNo = __cswiftslash_get_errno()
			try? pidfd.closeFileHandle()
			throw EventTriggerErrors.processRegistrationFailure(pid, errNo)
		}
		activeProcessPidfds[pid] = pidfd
	}

	@SwiftSlashGlobalSerialization internal static func deregister(_ ev:EventTriggerHandlePrimitive, process pid:Int32) throws(EventTriggerErrors) {
		guard let pidfd = activeProcessPidfds.removeValue(forKey:pid) else {
			// never registered (or already deregistered). nothing to do.
			return
		}
		var buildEvent = epoll_event()
		buildEvent.data.fd = pid
		buildEvent.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
		let deleteReturn = epoll_ctl(ev, EPOLL_CTL_DEL, pidfd, &buildEvent)
		try? pidfd.closeFileHandle()
		guard deleteReturn == 0 else {
			throw EventTriggerErrors.processDeregistrationFailure(pid, __cswiftslash_get_errno())
		}
	}
}
#endif