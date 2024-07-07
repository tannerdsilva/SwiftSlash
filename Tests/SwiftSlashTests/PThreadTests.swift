import XCTest
@testable import SwiftSlash
import Logging
// import Glibc
import __cswiftslash

class PThreadTests: XCTestCase {
    // func testPThreadCancellation() async throws {
    //     let expectation = XCTestExpectation(description: "PThread cancellation")
    //     expectation.isInverted = true
    //     let logger = Logger(label: "testLogger")
    //     var pthread = try await PThread(logger: logger) { logger in
    //         // Simulate a long-running task
    //         sleep(5)
    //         expectation.fulfill()
    //     }
	// 	try await pthread.start()
        
    //     // Cancel the pthread
    //     try pthread.cancel()

	// 	try await pthread.waitForResult()
        
    //     // Wait for the expectation to be fulfilled
    //    wait(for: [expectation], timeout: 10)
	// }
    
    // func testPThreadJoin() async throws {
    //     let expectation = XCTestExpectation(description: "PThread join")
        
    //     let logger = Logger(label: "testLogger")
    //     var pthread = try await PThread(logger: logger) { logger in
    //         sleep(5)
    //         expectation.fulfill()
    //     }
    //     try await pthread.start()
		
    //     // Join the pthread
    //     await pthread.waitForResult()
        
    //     // Wait for the expectation to be fulfilled
    //     wait(for: [expectation], timeout: 10)
    // }
    
    func testPThreadDeinit() async throws {
        let expectation = XCTestExpectation(description: "PThread deinit")
        func nestedFunc() async throws {
			let logger = Logger(label: "testLogger")
			var pthread:PThread = try await PThread(allocate: { return nil }, dealloc: { _ in })
			try await pthread.start({ argPtr, wsPtr in
				// Create epoll instance
				let epollFD = epoll_create1(0)
				defer {
					close(epollFD)
				}
				XCTAssert(epollFD != -1, "Failed to create epoll instance")

				// Define epoll event
				var event = epoll_event(events: EPOLLIN.rawValue, data: epoll_data_t(fd: 0))  // Setup with dummy data
				var events = [epoll_event](repeating: event, count: 1)

				// Define the signal mask
				var sigmask = sigset_t()
				// Prepare the signal mask to block all signals except SIGUSR1
				sigemptyset(&sigmask);
				sigaddset(&sigmask, SIGUSR1);
		
				// Start epoll wait
				// logger.info("PThread started, entering epoll_wait")
				let n = epoll_pwait(epollFD, &events, 1, -1, &sigmask)
				// notExpectation.fulfill()
			})
			sleep(1)
		}

		var error:Swift.Error? = nil
		do {
			try await nestedFunc()
			sleep(1)
		} catch let e {
			error = e
		}

		XCTAssertNil(error)
    }

// class EPollPThreadCancellationTest: XCTestCase {
    func testEPollPThreadCancellationImmediate() async throws {
        let expectation = XCTestExpectation(description: "epoll_wait should be interrupted by pthread cancellation")
		let notExpectation = XCTestExpectation(description: "epoll_wait should not be interrupted by pthread cancellation")
		notExpectation.isInverted = true

        // Logger for debugging purposes
        let logger = Logger(label: "testLogger")


        var pthread = try await PThread(allocate: { return nil }, dealloc: { _ in })

        try await pthread.start({ argPtr, wsPtr in
		    // Create epoll instance
			let epollFD = epoll_create1(0)
			defer {
				close(epollFD)
			}
			XCTAssert(epollFD != -1, "Failed to create epoll instance")

            // Define epoll event
            var event = epoll_event(events: EPOLLIN.rawValue, data: epoll_data_t(fd: 0))  // Setup with dummy data
            var events = [epoll_event](repeating: event, count: 1)

			// Define the signal mask
            var sigmask = sigset_t()
            // Prepare the signal mask to block all signals except SIGUSR1
			sigemptyset(&sigmask);
			sigaddset(&sigmask, SIGUSR1);
	
            // Start epoll wait
            // logger.info("PThread started, entering epoll_wait")
            let n = epoll_pwait(epollFD, &events, 1, -1, &sigmask)
            // notExpectation.fulfill()
        })

        // Cancel the pthread
        try pthread.cancel()

        let result = try await pthread.waitForResult()
		print("got result: \(result)")
		switch result {
		case .success:
			XCTFail("PThread should have been cancelled")
		case .failure(let error):
			switch error {
				case is CancellationError:
					XCTAssertTrue(true)
					break;
				default:
					XCTFail("Unexpected error: \(error)")
			}
		}
        // Wait for the expectation to be fulfilled
        wait(for: [expectation, notExpectation], timeout:0)
    }
}