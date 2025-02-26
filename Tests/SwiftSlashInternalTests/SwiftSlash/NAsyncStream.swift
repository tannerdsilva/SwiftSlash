/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Testing
@testable import SwiftSlashNAsyncStream

extension Tag {
	@Tag internal static var swiftSlashNAsyncStream:Self
}

extension SwiftSlashTests {
	@Suite("SwiftSlashNAsyncStream",
		.serialized,
		.tags(.swiftSlashNAsyncStream)
	)
	struct NAsyncStreamTests {
		@Test("SwiftSlashNAsyncStream :: basic usage and memory management")
		func testNAsyncStreamMemoryManagement() async {
			let stream = NAsyncStream<WhenDeinitTool<Int>, Never>()
			await confirmation("confirm correct memory management throughout lifecycle", expectedCount:3) { deinitConf in
				await withTaskGroup(of:Void.self) { tg in
					tg.addTask { [asT = stream.makeAsyncConsumer()] in
						var result:[Int] = []
						while let item = await asT.next(whenTaskCancelled:.noAction) {
							result.append(item.value)
						}
						#expect(result == [1, 2, 3])
					}
					stream.yield(WhenDeinitTool(1, deinitConf))
					stream.yield(WhenDeinitTool(2, deinitConf))
					stream.yield(WhenDeinitTool(3, deinitConf))
					stream.finish()
					await tg.waitForAll()
				}
			}
		}

		@Test("SwiftSlashNAsyncStream :: testing large number of elements")
		func testNasyncStreamLargeElementCount() async {
			let elementCount = 10000
			let stream = NAsyncStream<WhenDeinitTool<Int>, Never>()
			await confirmation("confirm correct memory management throughout lifecycle", expectedCount:elementCount) { deinitConf in
				await withTaskGroup(of:Void.self) { tg in
					tg.addTask { [asT = stream.makeAsyncConsumer()] in
						var result:[Int] = []
						while let item = await asT.next(whenTaskCancelled:.noAction) {
							result.append(item.value)
						}
						#expect(result == Array(1...elementCount))
					}
					for i in 1...elementCount {
						stream.yield(WhenDeinitTool(i, deinitConf))
					}
					stream.finish()
					await tg.waitForAll()
				}
			}
		}
	}
}