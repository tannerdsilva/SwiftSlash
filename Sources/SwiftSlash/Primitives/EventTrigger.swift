import CSwiftSlash

#if SWIFTSLASH_LOG_ENABLE
import Logging
#endif

internal actor EventTrigger {
	
	/// the initial allocation size for events to come in from the polling function.
	private let initialEventsAllocationSize:UInt16

	/// the current operating state of the event trigger.
	private var isRunning:Bool = false
	
	#if SWIFTSLASH_LOG_ENABLE
	/// the logger that is used to log events.
	private let logger:Logger?
	#endif

	#if SWIFTSLASH_LOG_ENABLE
	/// primary initializer.
	internal init(
		initialEventsAllocationSize:UInt16 = 32,
		logger:Logger?
	) {
		self.initialEventsAllocationSize = initialEventsAllocationSize
		self.logger = logger
	}
	#else
	/// primary initializer.
	internal init(
		initialEventsAllocationSize:UInt16 = 32
	) {
		self.initialEventsAllocationSize = initialEventsAllocationSize
	}
	#endif

	internal func run() async throws {

		// allocate memory for events to come in from the polling function.
		var eventsAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:32)
		defer {
			eventsAllocation.deallocate()
		}
		var allocationSize:Int32 = 32
		
		// define a function to allow us to resize this allocation in the future.
		func reallocate(size:Int32) {
			eventsAllocation.deallocate()
			eventsAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:Int(size))
			allocationSize = size
		}

		// loop that will recreate the system polling facility if it needs to be recreated for some reason.
		// i hope that this loop should never need to iterate, but i want to be able to support things like seteuid() and setegid() in the future, and I figure that this might be needed to support that.
		while Task.isCancelled == false {
			// acquire a new epoll facility from the system.
			let newEpoll = epoll_create1(0)
			defer {
				// close the epoll facility.
				close(newEpoll)
			}

			// primary loop for event handling.
			while Task.isCancelled == false {
				do {
					// wait for events to come in.
					let epollResult = try await withUnsafeThrowingContinuation { (pollCont:UnsafeContinuation<Int32, Swift.Error>) in 
						// poll wait.
						let epollResult = epoll_wait(newEpoll, eventsAllocation, allocationSize, -1) 
						switch epollResult {
							case -1:
								let captureErrno = getErrno()
								let descriptionString = String(cString:strerror(captureErrno))
								pollCont.resume(throwing:SystemPollingError(code:captureErrno, message:descriptionString))
							default:
								pollCont.resume(returning:epollResult)
						}
					}

					// act based on the result of the poll.
					switch epollResult {
						case 0:
							// no events to process.
							continue;
						default:
							// events to process.
							var i = 0
							while (i < epollResult) {
								// capture the current event.
								let currentEvent = eventsAllocation[i];
								
								// define the possible outcomes of the event.
								let pollin = currentEvent.events & EPOLLIN.rawValue
								let pollhup = currentEvent.events & EPOLLHUP.rawValue
								let pollout = currentEvent.events & EPOLLOUT.rawValue
								let pollerr = currentEvent.events & EPOLLERR.rawValue
								
								// act based on the outcome found.
								if (pollhup != 0) {
									// reading handle closed.
								} else if (pollerr != 0) {
									// writing handle closed.
								} else if (pollin != 0) {
									// read data available.
								} else if (pollout != 0) {
									// write data available.
								}

								i += 1
							}
					}
				}
			}
		}
	}
}