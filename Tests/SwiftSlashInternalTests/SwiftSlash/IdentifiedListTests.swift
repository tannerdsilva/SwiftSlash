// /*
// LICENSE MIT
// copyright (c) tanner silva 2025. all rights reserved.

//    _____      ______________________   ___   ______ __
//   / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
//  _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
// /___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

// */

// import Testing
// @testable import SwiftSlashIdentifiedList

// extension Tag {
// 	@Tag internal static var swiftSlashIdentifiedList:Self
// }

// extension SwiftSlashTests {
// 	@Suite("SwiftSlashIdentifiedListTests",
// 		.serialized,
// 		.tags(.swiftSlashIdentifiedList)
// 	)
// 	internal struct SwiftSlashIdentifiedListTests {
// 		@Test("SwiftSlashIdentifiedList :: test memory lifecycle", .timeLimit(.minutes(1)))
// 		func testIdentifiedListMemoryLifecycle() async {
// 			var il:IdentifiedList<WhenDeinitTool<Int>>? = IdentifiedList<WhenDeinitTool<Int>>()
// 			await confirmation("confirm that memory basics are correctly implemented in the identified list", expectedCount:2, { outerConfirm in
// 				let k1 = il!.insert(WhenDeinitTool(10, outerConfirm))
// 				let k3 = il!.insert(WhenDeinitTool(30, outerConfirm))
// 				var result:[UInt64:Int] = [:]
// 				await confirmation("confirm that memory basics are correctly implemented in the identified list", expectedCount:1, { innerConfirm in
// 					let k2 = il!.insert(WhenDeinitTool(20, innerConfirm))
// 					il!.forEach { k, value in
// 						result[k] = value.value
// 					}
// 					#expect(result == [k1:10, k2:20, k3:30])
// 					let removedValue = il!.remove(k2)?.value
// 					#expect(removedValue == 20)
// 					result = [:]
// 				})
// 				il!.forEach { k, value in
// 					result[k] = value.value
// 				}
// 				#expect(result == [k1:10, k3:30])
// 				il = nil
// 			})
// 		}

// 		@Test("SwiftSlashIdentifiedList :: test remove non-existing key", .timeLimit(.minutes(1)))
// 		func testIdentifiedListRemoveNonExistingKey() {
// 			let il = IdentifiedList<String>()
// 			let removedValue = il.remove(123)
// 			#expect(removedValue == nil)
// 		}

// 		@Test("SwiftSlashIdentifiedList :: test concurrent insert and remove", .timeLimit(.minutes(1)))
// 		func testIdentifiedListConcurrentInsertAndRemove() async {
// 			let il = IdentifiedList<Int>()
// 			let keptItems = await withTaskGroup(of:Optional<(UInt64, Int)>.self, returning:[UInt64:Int].self) { tg in
// 				for index in 0..<10000 {
// 					tg.addTask {
// 						let key = il.insert(index)
// 						if index % 2 == 0 {
// 							let removedValue = il.remove(key)
// 							#expect(removedValue == index)
// 							return nil
// 						}
// 						return (key, index)
// 					}
// 				}
// 				var buildKeepers = [UInt64:Int]()
// 				for await currentTask in tg {
// 					if let (key, value) = currentTask {
// 						buildKeepers[key] = value
// 					}
// 				}
// 				return buildKeepers
// 			}
// 			var result: [UInt64:Int] = [:]
// 			il.forEach { k, value in
// 				result[k] = value
// 			}
// 			#expect(result == keptItems)
// 		}
// 	}
// }