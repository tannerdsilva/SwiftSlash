import XCTest
@testable import SwiftSlash
import Logging

class PThreadTests: XCTestCase {
    func testPThreadCancellation() async throws {
        let expectation = XCTestExpectation(description: "PThread cancellation")
        expectation.isInverted = true
        let logger = Logger(label: "testLogger")
        var pthread = try await PThread(logger: logger) { logger in
            // Simulate a long-running task
            sleep(5)
            expectation.fulfill()
        }
		try await pthread.start()
        
        // Cancel the pthread
        try pthread.cancel()

		try await pthread.waitForResult()
        
        // Wait for the expectation to be fulfilled
        await fulfillment(of:[expectation], timeout: 10)
    }
    
    func testPThreadJoin() async throws {
        let expectation = XCTestExpectation(description: "PThread join")
        
        let logger = Logger(label: "testLogger")
        var pthread = try await PThread(logger: logger) { logger in
            sleep(5)
            expectation.fulfill()
        }
        try await pthread.start()
		
        // Join the pthread
        await pthread.waitForResult()
        
        // Wait for the expectation to be fulfilled
        await fulfillment(of: [expectation], timeout: 10)
    }
    
    func testPThreadDeinit() async throws {
        let expectation = XCTestExpectation(description: "PThread deinit")
        func nestedFunc() async throws {
			let logger = Logger(label: "testLogger")
			var pthread:PThread = try await PThread(logger: logger) { logger in
				// Simulate a long-running task
				sleep(5)
				expectation.fulfill()
			}
			try await pthread.start()
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
}