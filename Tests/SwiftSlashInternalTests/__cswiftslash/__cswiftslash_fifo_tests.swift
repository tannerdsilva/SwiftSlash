/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Testing

@testable import __cswiftslash_fifo

import class Foundation.ProcessInfo

extension Tag {
	@Tag internal static var __cswiftslash_fifo:Self
}

extension __cswiftslash_tests {
	@Suite("__cswiftslash_fifo",
		.serialized,
		.tags(.__cswiftslash_fifo)
	)
	internal struct __cswiftslash_fifo {
		// MARK: c harness
		private final class Harness:@unchecked Sendable {
			private let fifoPtr:UnsafeMutablePointer<__cswiftslash_fifo_linkpair_t>
			fileprivate init(hasMutex:Bool = true) {
				if hasMutex {
					fifoPtr = __cswiftslash_fifo_init(true)
				} else {
					fifoPtr = __cswiftslash_fifo_init(false)
				}
			}
			fileprivate func pass(_ data: UnsafeMutableRawPointer) -> Int8 {
				return __cswiftslash_fifo_pass(fifoPtr, data)
			}
			/// consumes data from the FIFO in a non-blocking manner
			fileprivate func consumeNonBlocking() -> (__cswiftslash_fifo_consume_result_t, UnsafeMutableRawPointer?) {
				var consumedData:UnsafeMutableRawPointer?
				let result = __cswiftslash_fifo_consume_nonblocking(fifoPtr, &consumedData)
				return (result, consumedData)
			}
			/// consumes data from the FIFO in a blocking manner
			fileprivate func consumeBlocking() async -> (__cswiftslash_fifo_consume_result_t, UnsafeMutableRawPointer?) {
				return await withUnsafeContinuation { (continuation:UnsafeContinuation<(__cswiftslash_fifo_consume_result_t, UnsafeMutableRawPointer?), Never>) in
					var consumedData:UnsafeMutableRawPointer?
					continuation.resume(returning:(__cswiftslash_fifo_consume_blocking(fifoPtr, &consumedData), consumedData))
				}
			}
			/// caps the FIFO with a final element
			fileprivate func passCap(_ capData: UnsafeMutableRawPointer?) -> Bool {
				return __cswiftslash_fifo_pass_cap(fifoPtr, capData)
			}
			/// sets the maximum number of elements in the FIFO
			fileprivate func setMaxElements(_ maxElements: size_t) -> Bool {
				return __cswiftslash_fifo_set_max_elements(fifoPtr, maxElements)
			}
			private func closeFIFO() -> (Bool, UnsafeMutableRawPointer?) {
				var cptr:UnsafeMutableRawPointer? = nil
				return (__cswiftslash_fifo_close(fifoPtr, { _, _ in }, nil, &cptr), cptr)
			}
			deinit {
				_ = closeFIFO()
			}
		}

		private var fifo:Harness? = Harness(hasMutex:true)

		@Test("__cswiftslash_fifo :: basic init and deinit", .timeLimit(.minutes(1)))
		mutating func basicInitDeinit() async {
			#expect(fifo != nil)
			fifo = nil
			#expect(fifo == nil)
			fifo = Harness(hasMutex:false)
			#expect(fifo != nil)
			fifo = nil
			#expect(fifo == nil)
		}

		// MARK: test cases

		@Test("__cswiftslash_fifo :: nonblocking consume from empty fifo", .timeLimit(.minutes(1)))
		func consumeFromEmpty() {
			let (consumeResult, consumedData) = fifo!.consumeNonBlocking()
			#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_WOULDBLOCK)
			#expect(consumedData == nil)
		}

		@Test("__cswiftslash_fifo :: pass then consume (single element - nonblocking)", .timeLimit(.minutes(1)))
		func passThenConsumeNBSimpleSingle() async {
			// pass data and ensure it succeeds
			let data = UnsafeMutableRawPointer(bitPattern: 0x1234)!
			let passResult = fifo!.pass(data)
			#expect(passResult == 0)
			
			// consume the data back
			let (consumeResult2, consumedData2) = fifo!.consumeNonBlocking()
			#expect(consumeResult2 == __CSWIFTSLASH_FIFO_CONSUME_RESULT)
			#expect(consumedData2 == data)
		}

		@Test("__cswiftslash_fifo :: pass then consume (single element - blocking)", .timeLimit(.minutes(1)))
		func passThenConsumeBSingle() async {
			// lass data and ensure it succeeds
			let data = UnsafeMutableRawPointer(bitPattern:0x2468)!
			let passResult = fifo!.pass(data)
			#expect(passResult == 0)

			// consume the data back
			let (consumedResult2, consumedData2) = await fifo!.consumeBlocking()
			#expect(consumedResult2 == __CSWIFTSLASH_FIFO_CONSUME_RESULT)
			#expect(consumedData2 == data)
		}

		static let fifoConsecutiveCount = 10

		@Test("__cswiftslash_fifo :: pass then consume (consecutive elements - nonblocking)", .timeLimit(.minutes(1)))
		func passThenConsumeSimpleMultiple() async {		
			
			for i in 0..<Self.fifoConsecutiveCount {
				let data = UnsafeMutablePointer<Int>.allocate(capacity: 1)
				data.pointee = i
				#expect(fifo!.pass(data) == 0)
			}
			for i in 0..<Self.fifoConsecutiveCount {
				let (consumeResult, consumedData) = fifo!.consumeNonBlocking()
				#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_RESULT)
				#expect(consumedData != nil)
				#expect(consumedData!.assumingMemoryBound(to: Int.self).pointee == i)
				consumedData!.deallocate()
			}
		}

		@Test("__cswiftslash_fifo :: pass then consume (consecutive elements - blocking)")
		func testPassAndConsumeMultiBlocking() async {
			for i in 0..<Self.fifoConsecutiveCount {
				let data = UnsafeMutablePointer<Int>.allocate(capacity: 1)
				data.pointee = i
				#expect(fifo!.pass(data) == 0)
			}
			for i in 0..<Self.fifoConsecutiveCount {
				let (consumeResult, consumedData) = await fifo!.consumeBlocking()
				#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_RESULT)
				#expect(consumedData != nil)
				#expect(consumedData!.assumingMemoryBound(to: Int.self).pointee == i)
				consumedData!.deallocate()
			}
		}

		@Test("__cswiftslash_fifo :: set max elements", .timeLimit(.minutes(1)))
		func testSetMaxElements() async {		
			let setResult = fifo!.setMaxElements(2)
			#expect(setResult == true)
			
			// pass two elements
			let data1 = UnsafeMutableRawPointer(bitPattern: 0x1)!
			let data2 = UnsafeMutableRawPointer(bitPattern: 0x2)!
			#expect(fifo!.pass(data1) == 0)
			#expect(fifo!.pass(data2) == 0)
			
			// attempt to pass a third element
			let data3 = UnsafeMutableRawPointer(bitPattern: 0x3)!
			#expect(fifo!.pass(data3) == -2)
			
			// consume one element
			let (consumeResult, consumedData) = fifo!.consumeNonBlocking()
			#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_RESULT)
			#expect(consumedData == data1)
			
			// now passing should succeed
			#expect(fifo!.pass(data3) == 0)
		}

		@Test("__cswiftslash_fifo :: fuzz testing FIFO", .timeLimit(.minutes(1)))
		mutating func testFuzzTestingFIFO() async throws {
			// reference tool used to document which elements are going into the FIFO in which order.
			actor ProductionDocumenter {
				var producedItems:[UInt8] = []
				func produced(_ item:UInt8) {
					producedItems.append(item)
				}
				func nextConsumed() -> UInt8? {
					guard producedItems.count > 0 else {
						return nil
					}
					return producedItems.removeFirst()
				}
			}
			
			fifo = Harness(hasMutex:true)	
			let bookKeeper = ProductionDocumenter()
			await withTaskGroup(of:[UInt8].self) { [fifo] group in
				group.addTask {
					var producedItems:[UInt8] = []
					for _ in 0..<Self.fifoConsecutiveCount {
						let data = UnsafeMutablePointer<UInt8>.allocate(capacity:1)
						data.pointee = UInt8.random(in: 0...UInt8.max)
						let producedByte = data.pointee
						await bookKeeper.produced(producedByte)
						_ = fifo!.pass(data)
						producedItems.append(producedByte)
					}
					return producedItems
				}
				group.addTask {
					var consumedItems:[UInt8] = []
					for _ in 0..<Self.fifoConsecutiveCount {
						let (consumeResult, consumedData) = await fifo!.consumeBlocking()
						#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_RESULT)
						let consumedByte = consumedData!.assumingMemoryBound(to:UInt8.self).pointee
						consumedData!.deallocate()
						// ensure the consumed byte is in the bookkeeper
						guard let expectedByte = await bookKeeper.nextConsumed() else {
							fatalError("expected byte not found in bookkeeper")
						}
						#expect(consumedByte == expectedByte)
						consumedItems.append(consumedByte)
					}
					return consumedItems
				}
				let producerResult = await group.next()
				let consumerResult = await group.next()
				#expect(producerResult == consumerResult)
			}
		}

		@Test("__cswiftslash_fifo :: blocking consume with cap", .timeLimit(.minutes(1)))
		func testBlockingConsumeWithCap() async {		
			let capData = UnsafeMutableRawPointer(bitPattern: 0xfeed)!
			#expect(fifo!.passCap(capData) == true)
			let (consumeResult, consumedData) = await fifo!.consumeBlocking()
			#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_CAP)
			#expect(consumedData == capData)
		}

		@Test("__cswiftslash_fifo :: set max elements to zero", .timeLimit(.minutes(1)))
		func testSetMaxElementsToZero() async {
			#expect(fifo!.setMaxElements(0) == true)
			
			// attempt to pass data
			let data = UnsafeMutableRawPointer(bitPattern: 0x1)!
			let passResult = fifo!.pass(data)
			#expect(passResult == -2) // max elements reached
		}

		@Test("__cswiftslash_fifo :: set max elements to 1", .timeLimit(.minutes(1)))
		func testSetMaxElementsToOne() async {
			#expect(fifo!.setMaxElements(1) == true)
			
			// pass data
			let data1 = UnsafeMutableRawPointer(bitPattern: 0x1)!
			let passResult1 = fifo!.pass(data1)
			#expect(passResult1 == 0)
			
			// attempt to pass a second element
			let data2 = UnsafeMutableRawPointer(bitPattern: 0x2)!
			let passResult2 = fifo!.pass(data2)
			#expect(passResult2 == -2) // max elements reached
			
			// consume the first element
			let (consumeResult, consumedData) = fifo!.consumeNonBlocking()
			#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_RESULT)
			#expect(consumedData == data1)
			
			// nothing left to consume
			let (consumeResult2, consumedData2) = fifo!.consumeNonBlocking()
			#expect(consumeResult2 == __CSWIFTSLASH_FIFO_CONSUME_WOULDBLOCK)
			#expect(consumedData2 == nil)
		}

		@Test("__cswiftslash_fifo :: set max elements to n, while passing n*2 elements", .timeLimit(.minutes(1)))
		func testSetMaxElementsToNWhilePassingN2() async {
			let maxElements = 5
			#expect(fifo!.setMaxElements(maxElements) == true)
			
			// pass 2n elements
			for i in 0..<(maxElements*2) {
				let data = UnsafeMutablePointer<Int>.allocate(capacity: 1)
				data.pointee = i
				if i < maxElements {
					#expect(fifo!.pass(data) == 0)
				} else {
					#expect(fifo!.pass(data) == -2)
					data.deallocate()
				}
			}
			
			// consume n elements
			for i in 0..<maxElements {
				let (consumeResult, consumedData) = fifo!.consumeNonBlocking()
				#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_RESULT)
				#expect(consumedData != nil)
				#expect(consumedData!.assumingMemoryBound(to: Int.self).pointee == i)
				consumedData!.deallocate()
			}
			
			// pass n elements
			for i in 0..<maxElements {
				let data = UnsafeMutablePointer<Int>.allocate(capacity: 1)
				data.pointee = i
				#expect(fifo!.pass(data) == 0)
			}
			
			// consume n elements
			for i in 0..<maxElements {
				let (consumeResult, consumedData) = fifo!.consumeNonBlocking()
				#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_RESULT)
				#expect(consumedData != nil)
				#expect(consumedData!.assumingMemoryBound(to: Int.self).pointee == i)
				consumedData!.deallocate()
			}
		}
	}
}