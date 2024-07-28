import XCTest
@testable import SwiftSlashNAsyncStream

class NAsyncStreamTests: XCTestCase {
    func testNAsyncStreamMemoryManagement() async {
        let stream = NAsyncStream<WhenDeinitTool<Int>, Never>()
        var deinitCount = 0
        func didDeinit() {
            deinitCount += 1
        }

        // Create a few consumers
		let delayedConsumer = stream.makeAsyncConsumer()
        let consumerTask1 = Task { [asT = stream.makeAsyncConsumer()] in
			var asyncStream = asT
            var result: [Int] = []
            while let item = try await asyncStream.next() {
                result.append(item.value)
            }
            XCTAssertEqual(result, [1, 2, 3])
        }

        // Produce data
        stream.yield(WhenDeinitTool(1, deinitClosure: didDeinit))
        stream.yield(WhenDeinitTool(2, deinitClosure: didDeinit))
        stream.yield(WhenDeinitTool(3, deinitClosure: didDeinit))
        stream.finish()

        // Wait for all consumer tasks to complete
        await consumerTask1.result

		let consumerTask2 = Task { [delayedConsumer] in
			var stream = delayedConsumer
            var result: [Int] = []
            while let item = try await stream.next() {
                result.append(item.value)
            }
            XCTAssertEqual(result, [1, 2, 3])
        }
        await consumerTask2.result

        // Ensure all elements were deinitialized properly
        XCTAssertEqual(deinitCount, 3) // Each item should be deinitialized once per consumer
    }
}