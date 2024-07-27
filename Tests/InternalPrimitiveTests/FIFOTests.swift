import XCTest
@testable import SwiftSlashFIFO

class FIFOTests: XCTestCase {
	func testFIFOWithDeinitTool() async {
		var fifo:FIFO<WhenDeinitTool<Int>, Never>? = FIFO<WhenDeinitTool<Int>, Never>()
		var deinitCount = 0
		func didDeinit() {
			deinitCount += 1
		}

		// Create an async task for consuming data
		let consumerTask = Task { [fifo] in
			var fifoIterator = fifo!.makeAsyncConsumer()
			do {
				var result: [Int] = []
				while let element = try await fifoIterator.next() {
					result.append(element.value)  // Access the value stored within WhenDeinitTool
				}
				XCTAssertEqual(result, [1, 2, 3, 4, 5])
			} catch {
				XCTFail("Error consuming data: \(error)")
			}
		}
		
		// Produce data wrapped in WhenDeinitTool
		fifo!.yield(WhenDeinitTool(1, deinitClosure: didDeinit))
		fifo!.yield(WhenDeinitTool(2, deinitClosure: didDeinit))
		fifo!.yield(WhenDeinitTool(3, deinitClosure: didDeinit))
		fifo!.yield(WhenDeinitTool(4, deinitClosure: didDeinit))
		fifo!.yield(WhenDeinitTool(5, deinitClosure: didDeinit))
		fifo!.finish()
		
		// Wait for the consumer task to complete
		await consumerTask.result
		
		// Ensure all elements were deinitialized properly
		XCTAssertEqual(deinitCount, 5)
	}
	func testNoConsumption() async {
		// now test the same scenario without any consumption. ensure that the references are deinitialized properly when the fifo is deinitialized.
		var fifo:FIFO<WhenDeinitTool<Int>, Never>? = FIFO<WhenDeinitTool<Int>, Never>()
		var deinitCount = 0
		func didDeinit() {
			deinitCount += 1
		}

		fifo!.yield(WhenDeinitTool(1, deinitClosure: didDeinit))
		fifo!.yield(WhenDeinitTool(2, deinitClosure:didDeinit))
		fifo!.yield(WhenDeinitTool(3, deinitClosure: didDeinit))
		fifo!.yield(WhenDeinitTool(4, deinitClosure: didDeinit))
		fifo!.yield(WhenDeinitTool(5, deinitClosure: didDeinit))

		// Deinitialize the fifo
		fifo = nil

		// Ensure all elements were deinitialized properly
		XCTAssertEqual(deinitCount, 5)
	}
	func testPartialConsumption() async {
		// test a partial consumption scenario. ensure that the references are deinitialized properly when the fifo is deinitialized.
		var fifo:FIFO<WhenDeinitTool<Int>, Never>? = FIFO<WhenDeinitTool<Int>, Never>()
		var deinitCount = 0
		func didDeinit() {
			deinitCount += 1
		}

		var fifoIterator:FIFO<WhenDeinitTool<Int>, Never>.AsyncConsumer? = fifo!.makeAsyncConsumer()
		let consumer = Task { [fi = fifoIterator!] in
			var fifoIterator = fi
			do {
				var result: [Int] = []
				while let element = try await fifoIterator.next() {
					result.append(element.value)  // Access the value stored within WhenDeinitTool
					if result.count == 3 {
						break
					}
				}
				XCTAssertEqual(result, [1, 2, 3])
			} catch {
				XCTFail("Error consuming data: \(error)")
			}
		}

		fifo!.yield(WhenDeinitTool(1, deinitClosure: didDeinit))
		fifo!.yield(WhenDeinitTool(2, deinitClosure: didDeinit))
		fifo!.yield(WhenDeinitTool(3, deinitClosure: didDeinit))
		fifo!.yield(WhenDeinitTool(4, deinitClosure: didDeinit))
		fifo!.yield(WhenDeinitTool(5, deinitClosure: didDeinit))

		await consumer.result

		XCTAssertEqual(deinitCount, 3)

		// Deinitialize the fifo
		fifo = nil
		fifoIterator = nil

		// Ensure all elements were deinitialized properly
		XCTAssertEqual(deinitCount, 5)
	}
}