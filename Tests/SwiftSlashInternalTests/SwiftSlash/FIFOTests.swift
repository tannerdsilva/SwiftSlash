import Testing
@testable import SwiftSlashFIFO

extension SwiftSlashTests {
	@Suite("SwiftSlashFIFO", .serialized)
	struct FIFOTests {
		@Test("SwiftSlashFIFO :: basic usage with deinitialization checks", .timeLimit(.minutes(1)))
		func testFIFOWithDeinitTool() async {
			let fifo:FIFO<WhenDeinitTool<Int>, Never>? = FIFO<WhenDeinitTool<Int>, Never>()
			var deinitCount = 0
			func didDeinit() {
				deinitCount += 1
			}

			let foundElements = await withTaskGroup(of:[Int].self, returning:[Int].self) { tg in
				tg.addTask { [asc = fifo!.makeAsyncConsumer()] in
					var buildInts = [Int]()
					var nextElement:WhenDeinitTool<Int>? = await asc.next()
					while nextElement != nil {
						buildInts.append(nextElement!.value)
						nextElement = await asc.next()
					}
					return buildInts
				}
				fifo!.yield(WhenDeinitTool(1, deinitClosure: didDeinit))
				fifo!.yield(WhenDeinitTool(2, deinitClosure: didDeinit))
				fifo!.yield(WhenDeinitTool(3, deinitClosure: didDeinit))
				fifo!.yield(WhenDeinitTool(4, deinitClosure: didDeinit))
				fifo!.yield(WhenDeinitTool(5, deinitClosure: didDeinit))
				fifo!.finish()
				return await tg.next()!
			}
			#expect(foundElements == [1, 2, 3, 4, 5])

			// ensure all elements were deinitialized properly
			#expect(deinitCount == 5)
		}

		@Test("SwiftSlashFIFO :: basic usage for no consumption", .timeLimit(.minutes(1)))
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
			#expect(deinitCount == 5)
		}
		@Test("SwiftSlashFIFO :: memory management in partial consumption scenario", .timeLimit(.minutes(1)))
		func testPartialConsumption() async {
			// test a partial consumption scenario. ensure that the references are deinitialized properly when the fifo is deinitialized.
			var fifo:FIFO<WhenDeinitTool<Int>, Never>? = FIFO<WhenDeinitTool<Int>, Never>()
			var deinitCount = 0
			func didDeinit() {
				deinitCount += 1
			}
			
			await withTaskGroup(of:[Int].self) { tg in
				tg.addTask { [asc = fifo!.makeAsyncConsumer()] in
					var buildInts = [Int]()
					var nextElement:WhenDeinitTool<Int>? = await asc.next()
					while nextElement != nil {
						buildInts.append(nextElement!.value)
						if buildInts.count == 3 {
							break
						} else {
							nextElement = await asc.next()
						}
					}
					return buildInts
				}
				fifo!.yield(WhenDeinitTool(1, deinitClosure: didDeinit))
				fifo!.yield(WhenDeinitTool(2, deinitClosure: didDeinit))
				fifo!.yield(WhenDeinitTool(3, deinitClosure: didDeinit))
				fifo!.yield(WhenDeinitTool(4, deinitClosure: didDeinit))
				fifo!.yield(WhenDeinitTool(5, deinitClosure: didDeinit))
				fifo!.finish()
				await tg.waitForAll()
			}

			#expect(deinitCount == 3)

			// Deinitialize the fifo
			fifo = nil
			// fifoIterator = nil

			// Ensure all elements were deinitialized properly
			#expect(deinitCount == 5)
		}
	}
}