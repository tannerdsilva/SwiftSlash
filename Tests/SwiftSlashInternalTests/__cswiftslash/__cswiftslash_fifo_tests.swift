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
			private let fifoPtr: UnsafeMutablePointer<__cswiftslash_fifo_linkpair_t>
			fileprivate init(hasMutex:Bool = false) {
				if hasMutex {
					var newMutex = pthread_mutex_t()
					_ = pthread_mutex_init(&newMutex, nil)
					fifoPtr = __cswiftslash_fifo_init(&newMutex)
				} else {
					fifoPtr = __cswiftslash_fifo_init(nil)
				}
			}
			fileprivate func pass(_ data: UnsafeMutableRawPointer) async -> Int8 {
				await withUnsafeContinuation { (continuation:UnsafeContinuation<Int8, Never>) in
					continuation.resume(returning:__cswiftslash_fifo_pass(fifoPtr, data))
				}
			}
			/// consumes data from the FIFO in a non-blocking manner
			fileprivate func consumeNonBlocking() -> (__cswiftslash_fifo_consume_result_t, UnsafeMutableRawPointer?) {
				var consumedData:UnsafeMutableRawPointer?
				let result = __cswiftslash_fifo_consume_nonblocking(fifoPtr, &consumedData)
				return (result, consumedData)
			}
			/// consumes data from the FIFO in a blocking manner
			fileprivate func consumeBlocking() async -> (__cswiftslash_fifo_consume_result_t, UnsafeMutableRawPointer?) {
				var consumedData:UnsafeMutableRawPointer?
				let result = await withUnsafeContinuation { (continuation:UnsafeContinuation<__cswiftslash_fifo_consume_result_t, Never>) in
					continuation.resume(returning:__cswiftslash_fifo_consume_blocking(fifoPtr, &consumedData))
				}
				return (result, consumedData)
			}
			/// caps the FIFO with a final element
			fileprivate func passCap(_ capData: UnsafeMutableRawPointer?) async -> Bool {
				return await withUnsafeContinuation { (continuation:UnsafeContinuation<Bool, Never>) in
					continuation.resume(returning:__cswiftslash_fifo_pass_cap(fifoPtr, capData))
				}
			}
			/// sets the maximum number of elements in the FIFO
			fileprivate func setMaxElements(_ maxElements: size_t) async -> Bool {
				return await withUnsafeContinuation { (continuation:UnsafeContinuation<Bool, Never>) in
					continuation.resume(returning:__cswiftslash_fifo_set_max_elements(fifoPtr, maxElements))
				}
			}
			private func close() -> UnsafeMutableRawPointer? {
				return __cswiftslash_fifo_close(fifoPtr, nil)
			}
			deinit {
				_ = close()
			}
		}

		private let fifo = Harness()

		// MARK: test cases
		@Test("__cswiftslash_fifo :: consume from empty FIFO", .timeLimit(.minutes(1)))
		func consumeFromEmpty() {				
			// attempt to consume from the empty FIFO
			let (consumeResult, consumedData) = fifo.consumeNonBlocking()
			#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_WOULDBLOCK)
			#expect(consumedData == nil)
		}

		@Test("__cswiftslash_fifo :: pass then consume simple (single element)", .timeLimit(.minutes(1)))
		func passThenConsumeSimpleSingle() async {
			// pass data and ensure it succeeds
			let data = UnsafeMutableRawPointer(bitPattern: 0x1)!
			let passResult = await fifo.pass(data)
			#expect(passResult == 0)
			
			// consume the data back
			let (consumeResult2, consumedData2) = fifo.consumeNonBlocking()
			#expect(consumeResult2 == __CSWIFTSLASH_FIFO_CONSUME_RESULT)
			#expect(consumedData2 == data)
		}

		@Test("__cswiftslash_fifo :: pass then consume simple (multiple elements)", .timeLimit(.minutes(1)))
		func passThenConsumeSimpleMultiple() async {		
			let capData = UnsafeMutableRawPointer(bitPattern: 0xfeedface)!
			let capResult = await fifo.passCap(capData)
			#expect(capResult == true)
			
			// attempt to pass data after cap
			let data = UnsafeMutableRawPointer(bitPattern: 0xcafebabe)!
			let passResult = await fifo.pass(data)
			#expect(passResult == -1)
			
			// consume cap data
			let (consumeResult, consumedData) = fifo.consumeNonBlocking()
			#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_CAP)
			#expect(consumedData == capData)
			
			// attempt to consume again
			let (consumeResult2, consumedData2) = fifo.consumeNonBlocking()
			#expect(consumeResult2 == __CSWIFTSLASH_FIFO_CONSUME_CAP)
			#expect(consumedData2 == capData)
		}

		@Test("__cswiftslash_fifo :: pass then consume complex (n elements)", .timeLimit(.minutes(1)))
		func testPassAndConsumeNElements() async {		
			let n = Int.random(in:100...500)
			
			// pass n elements
			for i in 0..<n {
				let data = UnsafeMutablePointer<Int>.allocate(capacity: 1)
				data.pointee = i
				#expect(await fifo.pass(data) == 0)
			}
			
			// consume n elements
			for i in 0..<n {
				let (consumeResult, consumedData) = fifo.consumeNonBlocking()
				#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_RESULT)
				#expect(consumedData != nil)
				#expect(consumedData!.assumingMemoryBound(to: Int.self).pointee == i)
				consumedData!.deallocate()
			}
		}

		@Test("__cswiftslash_fifo :: set max elements", .timeLimit(.minutes(1)))
		func testSetMaxElements() async {		
			let setResult = await fifo.setMaxElements(2)
			#expect(setResult == true)
			
			// pass two elements
			let data1 = UnsafeMutableRawPointer(bitPattern: 0x1)!
			let data2 = UnsafeMutableRawPointer(bitPattern: 0x2)!
			#expect(await fifo.pass(data1) == 0)
			#expect(await fifo.pass(data2) == 0)
			
			// attempt to pass a third element
			let data3 = UnsafeMutableRawPointer(bitPattern: 0x3)!
			#expect(await fifo.pass(data3) == -2)
			
			// consume one element
			let (consumeResult, consumedData) = fifo.consumeNonBlocking()
			#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_RESULT)
			#expect(consumedData == data1)
			
			// now passing should succeed
			#expect(await fifo.pass(data3) == 0)
		}

		@Test("__cswiftslash_fifo :: non-blocking vs blocking consume", .timeLimit(.minutes(1)))
		func testNonBlockingVsBlockingConsume() async throws {		
			// start a consumer task
			let consumer = Task {
				let (consumeResult, consumedData) = await fifo.consumeBlocking()
				#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_RESULT)
				#expect(consumedData == UnsafeMutableRawPointer(bitPattern: 0xabc)!)
			}
			
			// simulate delay
			try await Task.sleep(nanoseconds: 100_000_000) // 100ms
			
			// pass data
			let data = UnsafeMutableRawPointer(bitPattern: 0xabc)!
			#expect(await fifo.pass(data) == 0)
			
			// wait for consumer to finish
			await consumer.value
		}

		@Test("__cswiftslash_fifo :: fuzz testing FIFO", .timeLimit(.minutes(1)))
		func testFuzzTestingFIFO() async {		
			let iterations = 10000
			
			await withTaskGroup(of: Void.self) { group in
				for _ in 0..<iterations {
					group.addTask {
						let action = Int.random(in: 0...1)
						if action == 0 {
							// producer
							let data = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
							data.storeBytes(of: UInt8.random(in: 0...255), as: UInt8.self)
							_ = await fifo.pass(data)
						} else {
							// consumer
							let (consumeResult, consumedData) = fifo.consumeNonBlocking()
							if consumeResult == __CSWIFTSLASH_FIFO_CONSUME_RESULT, let data = consumedData {
								data.deallocate()
							}
						}
					}
				}
			}
			
			// clean up any remaining data
			while true {
				let (consumeResult, consumedData) = fifo.consumeNonBlocking()
				if consumeResult == __CSWIFTSLASH_FIFO_CONSUME_RESULT, let data = consumedData {
					data.deallocate()
				} else {
					break
				}
			}
		}

		@Test("__cswiftslash_fifo :: blocking consume with cap", .timeLimit(.minutes(1)))
		func testBlockingConsumeWithCap() async {		
			// cap the FIFO
			let capData = UnsafeMutableRawPointer(bitPattern: 0xfeed)!
			#expect(await fifo.passCap(capData) == true)
			
			// start a consumer task
			let consumer = Task {
				let (consumeResult, consumedData) = await fifo.consumeBlocking()
				#expect(consumeResult == __CSWIFTSLASH_FIFO_CONSUME_CAP)
				#expect(consumedData == capData)
			}
			
			// wait for consumer to finish
			await consumer.value
		}

		@Test("__cswiftslash_fifo :: set max elements to zero", .timeLimit(.minutes(1)))
		func testSetMaxElementsToZero() async {
			#expect(await fifo.setMaxElements(0) == true)
			
			// attempt to pass data
			let data = UnsafeMutableRawPointer(bitPattern: 0x1)!
			let passResult = await fifo.pass(data)
			#expect(passResult == -2) // max elements reached
		}
	}
}