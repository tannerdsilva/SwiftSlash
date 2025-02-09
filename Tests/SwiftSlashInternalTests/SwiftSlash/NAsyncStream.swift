import Testing
@testable import SwiftSlashNAsyncStream

extension SwiftSlashTests {
	@Suite("SwiftSlashNAsyncStream", .serialized)
	struct NAsyncStreamTests {
		@Test("SwiftSlashNAsyncStream :: basic usage and memory management")
		func testNAsyncStreamMemoryManagement() async {
			let stream = NAsyncStream<WhenDeinitTool<Int>, Never>()
			var deinitCount = 0
			func didDeinit() {
				deinitCount += 1
			}

			await withTaskGroup(of:Void.self) { tg in
				tg.addTask { [asT = stream.makeAsyncConsumer()] in
					var result: [Int] = []
					while let item = await asT.next(whenTaskCancelled:.noAction) {
						result.append(item.value)
					}
					#expect(result == [1, 2, 3])
				}
				stream.yield(WhenDeinitTool(1, deinitClosure: didDeinit))
				stream.yield(WhenDeinitTool(2, deinitClosure: didDeinit))
				stream.yield(WhenDeinitTool(3, deinitClosure: didDeinit))
				stream.finish()
				await tg.waitForAll()
			}
			
			// ensure all elements were deinitialized properly
			#expect(deinitCount == 3)
		}
	}
}