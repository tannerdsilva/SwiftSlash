import CSwiftSlash

internal actor EventTrigger {
	fileprivate var epoll = epoll_create1(0);
	fileprivate func _mainLoop() async throws {
		// allocate memory for events to come in from the polling function.
		var eventsAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:32)
		var allocationSize:Int32 = 32
		// define a function to allow us to resize this allocation in the future.
		func reallocate(size:Int32) {
			eventsAllocation.deallocate()
			eventsAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:Int(size))
			allocationSize = size
		}

		// main loop
		while true {
			try await withUnsafeThrowingContinuation { (pollCont:UnsafeThrowingContinuation<Int>) in 
				let pollResult = epoll_wait(epoll, eventsAllocation, allocationSize, -1);
			}
			let pollResult = epoll_wait(epoll, eventsAllocation, allocationSize, -1);
			switch pollResult {
				case -1:
					// this code needs to be handled better before production
					fatalError("ET ERROR: HANDLE THIS BETTER PLEASE \(getErrno())");
				default:
					if (pollResult > 0) {
						var i = 0
						while (i < pollResult) {
							let currentEvent = eventsAllocation[i];
							
							let pollin = currentEvent.events & EPOLLIN.rawValue
							let pollhup = currentEvent.events & EPOLLHUP.rawValue
							let pollout = currentEvent.events & EPOLLOUT.rawValue
							let pollerr = currentEvent.events & EPOLLERR.rawValue
							
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