import Testing
@testable import SwiftSlashIdentifiedList

extension SwiftSlashTests {
	@Suite("SwiftSlashIdentifiedListTests",
		.serialized
	)
	internal struct SwiftSlashIdentifiedListTests {
		@Test("SwiftSlashIdentifiedList :: test memory lifecycle", .timeLimit(.minutes(1)))
		func testIdentifiedListMemoryLifecycle() {
			var il:IdentifiedList<WhenDeinitTool<Int>>? = IdentifiedList<WhenDeinitTool<Int>>()
			var diCount = 0
			func didDeinit() {
				diCount += 1
			}
			let k1 = il!.insert(WhenDeinitTool(10, deinitClosure:didDeinit))
			let k2 = il!.insert(WhenDeinitTool(20, deinitClosure:didDeinit))
			let k3 = il!.insert(WhenDeinitTool(30, deinitClosure:didDeinit))
			var result:[UInt64:Int] = [:]
			il!.forEach { k, value in
				result[k] = value.value
			}
			#expect(result == [k1:10, k2:20, k3:30])
			let removedValue = il!.remove(k2)?.value
			#expect(removedValue == 20)

			// check if the removed element is no longer present
			result = [:]
			il!.forEach { k, value in
				result[k] = value.value
			}
			#expect(result == [k1:10, k3:30])

			// check if the deinit closure is called
			#expect(diCount == 1)

			// deinitialize the atomic list
			il = nil

			// check if the deinit closure is called for the remaining elements
			#expect(diCount == 3)
		}

		@Test("SwiftSlashIdentifiedList :: test remove non-existing key", .timeLimit(.minutes(1)))
		func testIdentifiedListRemoveNonExistingKey() {
			let il = IdentifiedList<String>()
			let removedValue = il.remove(123)
			#expect(removedValue == nil)
		}

		@Test("SwiftSlashIdentifiedList :: test concurrent insert and remove", .timeLimit(.minutes(1)))
		func testIdentifiedListConcurrentInsertAndRemove() async {
			let il = IdentifiedList<Int>()
			let keptItems = await withTaskGroup(of:Optional<(UInt64, Int)>.self, returning:[UInt64:Int].self) { tg in
				for index in 0..<100 {
					tg.addTask {
						let key = il.insert(index)
						if index % 2 == 0 {
							let removedValue = il.remove(key)
							#expect(removedValue == index)
							return nil
						}
						return (key, index)
					}
				}
				var buildKeepers = [UInt64:Int]()
				for await currentTask in tg {
					if let (key, value) = currentTask {
						buildKeepers[key] = value
					}
				}
				return buildKeepers
			}
			var result: [UInt64:Int] = [:]
			il.forEach { k, value in
				result[k] = value
			}
			#expect(result == keptItems)
		}
	}
}