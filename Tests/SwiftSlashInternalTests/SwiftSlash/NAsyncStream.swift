import Testing
// @testable import SwiftSlashNAsyncStream

extension SwiftSlashTests {
	@Suite("SwiftSlashNAsyncStream", .serialized)
	struct NAsyncStreamTests {
		/*@Test("SwiftSlashNAsyncStream :: basic usage and memory management")
		func testNAsyncStreamMemoryManagement() async {
			let stream = NAsyncStream<WhenDeinitTool<Int>, Never>()
			await confirmation("confirm correct memory management throughout lifecycle", expectedCount:3) { deinitConf in
				await withTaskGroup(of:Void.self) { tg in
					tg.addTask { [asT = stream.makeAsyncConsumer()] in
						var result: [Int] = []
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
		}*/
	}
}