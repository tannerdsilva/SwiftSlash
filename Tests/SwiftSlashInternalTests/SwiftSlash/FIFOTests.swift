/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Testing
@testable import SwiftSlashFIFO

extension Tag {
	@Tag internal static var swiftSlashFIFO:Self
}

extension SwiftSlashTests {
	@Suite("SwiftSlashFIFO", 
		.serialized,
		.tags(.swiftSlashFIFO)
	)
	struct FIFOTests {
		@Test("SwiftSlashFIFO :: basic usage with deinitialization checks", .timeLimit(.minutes(1)))
		func testFIFOWithDeinitTool() async {
			var fifo:FIFO<WhenDeinitTool<Int>, Never>? = FIFO<WhenDeinitTool<Int>, Never>()
			fifo = nil
			#expect(fifo == nil)
		}

		@Test("SwiftSlashFIFO :: basic usage for no consumption", .timeLimit(.minutes(1)))
		func testNoConsumption() async {
			// now test the same scenario without any consumption. ensure that the references are deinitialized properly when the fifo is deinitialized.
			var fifo:FIFO<WhenDeinitTool<Int>, Never>? = FIFO<WhenDeinitTool<Int>, Never>()
			await confirmation("verify correct memory management of elements passed to the fifo", expectedCount:5) { deinitExp in
				fifo!.yield(WhenDeinitTool(1, deinitExp))
				fifo!.yield(WhenDeinitTool(2, deinitExp))
				fifo!.yield(WhenDeinitTool(3, deinitExp))
				fifo!.yield(WhenDeinitTool(4, deinitExp))
				fifo!.yield(WhenDeinitTool(5, deinitExp))
				fifo = nil
			}
		}
		@Test("SwiftSlashFIFO :: memory management in partial consumption scenario", .timeLimit(.minutes(1)))
		func testPartialConsumption() async {
			// test a partial consumption scenario. ensure that the references are deinitialized properly when the fifo is deinitialized.
			var fifo:FIFO<WhenDeinitTool<Int>, Never>? = FIFO<WhenDeinitTool<Int>, Never>()
			await confirmation("verify correct memory management of elements passed to the fifo", expectedCount:2) { deinitOuter in
				await withTaskGroup(of:[Int].self) { tg in
					await confirmation("verify correct memory management of elements passed to the fifo", expectedCount:3) { deinitInner in
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
						fifo!.yield(WhenDeinitTool(1, deinitInner))
						fifo!.yield(WhenDeinitTool(2, deinitInner))
						fifo!.yield(WhenDeinitTool(3, deinitInner))
						fifo!.yield(WhenDeinitTool(4, deinitOuter))
						fifo!.yield(WhenDeinitTool(5, deinitOuter))
						fifo!.finish()
						await tg.waitForAll()
					}
				}
				fifo = nil
			}
		}

		@Test("SwiftSlashFIFO :: testing large number of elements", .timeLimit(.minutes(1)))
		func testFullConsumption() async {
			let elementCount = 10000
			// test a full consumption scenario. ensure that the references are deinitialized properly when the fifo is deinitialized.
			let fifo:FIFO<WhenDeinitTool<Int>, Never>? = FIFO<WhenDeinitTool<Int>, Never>()
			await confirmation("verify correct memory management of elements passed to the fifo", expectedCount:elementCount) { deinitOuter in
				await withTaskGroup(of:[Int].self) { tg in
					tg.addTask { [asc = fifo!.makeAsyncConsumer()] in
						var buildInts = [Int]()
						var nextElement:WhenDeinitTool<Int>? = await asc.next()
						while nextElement != nil {
							buildInts.append(nextElement!.value)
							nextElement = await asc.next()
						}
						return buildInts
					}
					var written = [Int]()
					for i in 0..<elementCount {
						fifo!.yield(WhenDeinitTool(i, deinitOuter))
						written.append(i)
					}
					fifo!.finish()
					#expect(await tg.next() == written)
				}
			}
		}

		@Test("SwiftSlashFIFO :: intentional overflow of maximum element count", .timeLimit(.minutes(1)))
		func testMaxElementOverflow() async {
			let writeCount = 10000
			let maxCount = 10
			// test a full consumption scenario. ensure that the references are deinitialized properly when the fifo is deinitialized.
			var fifo:FIFO<WhenDeinitTool<Int>, Never>? = FIFO<WhenDeinitTool<Int>, Never>(maximumElementCount:maxCount)
			await confirmation("verify correct memory management of elements passed to the fifo", expectedCount:writeCount) { deinitThing in
				await withTaskGroup(of:[Int].self) { tg in
					var written = [Int]()
					for i in 0..<writeCount {
						if i < maxCount {
							#expect(fifo!.yield(WhenDeinitTool(i, deinitThing)) == .success)
						} else {
							#expect(fifo!.yield(WhenDeinitTool(i, deinitThing)) == .fifoFull)
						}
						written.append(i)
					}
					tg.addTask { [asc = fifo!.makeAsyncConsumer()] in
						var buildInts = [Int]()
						var nextElement:WhenDeinitTool<Int>? = await asc.next()
						while nextElement != nil {
							buildInts.append(nextElement!.value)
							nextElement = await asc.next()
						}
						return buildInts
					}
					fifo!.finish()
					let expected = Array(written.prefix(10))
					let foundItem = await tg.next()!
					#expect(expected == foundItem, "\(foundItem) != \(expected)")
					fifo = nil
				}
			}
		}
	}
}