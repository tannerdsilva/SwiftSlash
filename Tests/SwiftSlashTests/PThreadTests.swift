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
    
    // func testPThreadJoin() throws {
    //     let expectation = XCTestExpectation(description: "PThread join")
        
    //     let logger = Logger(label: "testLogger")
    //     var pthread = try PThread(alloc: { return nil }, dealloc: { _ in }) { argPtr, wsPtr in
	// 		// Simulate a long-running task
	// 		sleep(5)
	// 		// expectation.fulfill()
	// 	}
		
    //     // Join the pthread
    //     // try await pthread.waitForResult()
        
    //     // Wait for the expectation to be fulfilled
    //     // wait(for: [expectation], timeout: 10)
    // }
    
    // func testPThreadDeinit() async throws {
    //     let expectation = XCTestExpectation(description: "PThread deinit")
    //     func nestedFunc() async throws {
	// 		let logger = Logger(label: "testLogger")
	// 		var pthread:PThread = try await PThread(alloc: { return nil }, dealloc: { _ in }) { argPtr, wsPtr in
	// 			sleep(5)
	// 		}
	// 		sleep(1)
	// 	}

	// 	var error:Swift.Error? = nil
	// 	do {
	// 		try await nestedFunc()
	// 		sleep(1)
	// 	} catch let e {
	// 		error = e
	// 	}

	// 	XCTAssertNil(error)
    // }

// class EPollPThreadCancellationTest: XCTestCase {
#if os(Linux)
    func testEPollPThreadCancellationImmediate() async throws {
        let expectation = XCTestExpectation(description: "epoll_wait should be interrupted by pthread cancellation")
		let notExpectation = XCTestExpectation(description: "epoll_wait should not be interrupted by pthread cancellation")
		notExpectation.isInverted = true

        // Logger for debugging purposes
        let logger = Logger(label: "testLogger")

		final class ws {
			var epollFD:Int32
			var sigmask:sigset_t
			var events:UnsafeMutablePointer<epoll_event>
			var eventsCount:Int32 = 1

			var n:Int32 = 0
			init() {
				self.epollFD = epoll_create1(0)
				// Define the signal mask
				var sm = sigset_t()
				sigemptyset(&sm);
				sigaddset(&sm, SIGUSR1);
				self.sigmask = sm
				self.events = UnsafeMutablePointer<epoll_event>.allocate(capacity:1)
				self.eventsCount = 1
			}
			deinit {
				print("Deinit")
				close(epollFD)
				events.deallocate()
			}
		}
		let getThing = try await withThrowingTaskGroup(of:Void.self, returning:Void.self) { tg in
			tg.addTask {
				switch try await PThread<ws, ws, Void>.run(arg:ws(), work: { wsPtr in
					sleep(1)
					return
					wsPtr.pointee.n = epoll_pwait(wsPtr.pointee.epollFD, wsPtr.pointee.events, 1, -1, &wsPtr.pointee.sigmask)
				}) {
					case .failure(let error):
						expectation.fulfill()
					default:
						XCTFail("PThread should have been cancelled")
				}
				// expectation.fulfill()
			}
			try await Task.sleep(nanoseconds:2_000_000_000)
			// tg.cancelAll()
			try await Task.sleep(nanoseconds:1_000_000_000)
			// try await tg.waitForAll()	
			// wait(for: [expectation], timeout:0)
			return
		}
		return
		

		// try withUnsafePointer(to:notExpectation) { notExpectationPtr in
		// 	var pthread = try PThread(argument:notExpectationPtr, alloc: { return nil }, dealloc: { _ in }, { argPtr, wsPtr in
		// 		// Create epoll instance
		// 		let epollFD = epoll_create1(0)
		// 		defer {
		// 			close(epollFD)
		// 		}
		// 		XCTAssert(epollFD != -1, "Failed to create epoll instance")

		// 		// Start epoll wait
		// 		// logger.info("PThread started, entering epoll_wait")
		// 		let n = epoll_pwait(epollFD, &events, 1, -1, &sigmask)
		// 		argPtr!.assumingMemoryBound(to: XCTestExpectation.self).pointee.fulfill()
		// 	})


		// 	// Start the pthread
		// 	let future = try pthread.start()

		// 	// Cancel the pthread
		// 	try pthread.cancel()

		// 	let result = try future.waitForResult()
		// 	switch result {
		// 	case .success:
		// 		XCTFail("PThread should have been cancelled")
		// 	case .failure(let error):
		// 		switch error {
		// 			case is CancellationError:
		// 				expectation.fulfill()
		// 				break;
		// 			default:
		// 				XCTFail("Unexpected error: \(error)")
		// 		}
		// 	}
			// Wait for the expectation to be fulfilled

		
    }
	#endif
}