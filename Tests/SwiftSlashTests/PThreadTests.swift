import XCTest
@testable import SwiftSlash
import Logging

class PThreadTests: XCTestCase {
    // func testPThreadCancellation() throws {
    //     let expectation = XCTestExpectation(description: "PThread cancellation")
        
    //     let logger = Logger(label: "testLogger")
    //     var pthread = try PThread(logger: logger) { logger in
    //         // Simulate a long-running task
    //         sleep(5)
    //         expectation.fulfill()
    //     }
        
    //     // Cancel the pthread
    //     try pthread.cancel()
        
    //     // Wait for the expectation to be fulfilled
    //     wait(for: [expectation], timeout: 10)
    // }
    
    func testPThreadJoin() async throws {
        let expectation = XCTestExpectation(description: "PThread join")
        
        let logger = Logger(label: "testLogger")
        let pthread = try PThread(logger: logger) { logger in
            sleep(5)
            expectation.fulfill()
        }
        
        // Join the pthread
        await pthread.waitForResult()
        
        // Wait for the expectation to be fulfilled
        wait(for: [expectation], timeout: 10)
    }
    
    func testPThreadDeinit() async throws {
        let expectation = XCTestExpectation(description: "PThread deinit")
        func nestedFunc() async throws {
			let logger = Logger(label: "testLogger")
			var pthread:PThread = try PThread(logger: logger) { logger in
				// Simulate a long-running task
				sleep(5)
				expectation.fulfill()
			}
			sleep(1)
			try pthread.cancel()
			await pthread.waitForResult()
		}

		var error:Swift.Error? = nil
		do {
			try await nestedFunc()
		} catch let e {
			error = e
		}

		XCTAssertNil(error)
    }
}