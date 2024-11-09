/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Testing

import __cswiftslash_identified_list

@Suite("__cswiftslash_identified_list",
	.serialized
)
internal struct IdentifiedList {
	private actor KeyManager {
		private var keys:[UInt64] = []
		fileprivate func addKey(_ key: UInt64) {
			keys.append(key)
		}
		fileprivate func removeRandomKey() -> UInt64? {
			guard !keys.isEmpty else {
				return nil
			}
			let index = Int.random(in: 0..<keys.count)
			return keys.remove(at: index)
		}

		fileprivate func auditKeys() -> [UInt64] {
			return keys
		}
	}

	fileprivate final class IdentifiedListHarness:@unchecked Sendable {
		fileprivate let listPtr:UnsafeMutablePointer<__cswiftslash_identified_list_pair_t>
		
		/// initializes a new atomic list instance.
		fileprivate init() {
			listPtr = UnsafeMutablePointer<__cswiftslash_identified_list_pair_t>.allocate(capacity:1)
			listPtr.initialize(to:__cswiftslash_identified_list_init())
		}
		
		/// inserts a data pointer into the atomic list.
		@discardableResult fileprivate func insert(_ data:UnsafeMutableRawPointer) async -> UInt64 {
			return await withUnsafeContinuation { (cont:UnsafeContinuation<UInt64, Never>) in
				cont.resume(returning:__cswiftslash_identified_list_insert(listPtr, data))
			}
		}
		
		/// removes a data pointer from the atomic list by key.
		fileprivate func remove(key:UInt64) async -> UnsafeMutableRawPointer? {
			return await withUnsafeContinuation { (cont:UnsafeContinuation<UnsafeMutableRawPointer?, Never>) in
				cont.resume(returning:__cswiftslash_identified_list_remove(listPtr, key))
			}
		}
		
		/// iterates over the atomic list, processing each element with the provided consumer function.
		fileprivate func iterate(consumer:@escaping (UInt64, UnsafeMutableRawPointer?) -> Void) async {
			let cc = Unmanaged.passRetained(ConsumerContext(consumer)).toOpaque()
			await withUnsafeContinuation { (cont:UnsafeContinuation<Void, Never>) in
				__cswiftslash_identified_list_iterate(listPtr, IdentifiedListHarness.consumerFunction, cc)
				cont.resume()
			}
			_ = Unmanaged<ConsumerContext>.fromOpaque(cc).takeRetainedValue()
		}
		
		/// closes the atomic list, deallocating any remaining elements.
		fileprivate func close(consumer:@escaping ((UInt64, UnsafeMutableRawPointer?) -> Void) = { _, _ in }) async {
			let cc = Unmanaged.passRetained(ConsumerContext(consumer)).toOpaque()
			await withUnsafeContinuation { (cont:UnsafeContinuation<Void, Never>) in
				__cswiftslash_identified_list_close(listPtr, IdentifiedListHarness.consumerFunction, cc)
				cont.resume()
			}
			_ = Unmanaged<ConsumerContext>.fromOpaque(cc).takeRetainedValue()
		}

		deinit {
			self.listPtr.deinitialize(count: 1)
			self.listPtr.deallocate()
		}
		
		// MARK: - Helper Structures and Functions
		
		/// context to pass the consumer closure
		private final class ConsumerContext {
			fileprivate let consumer:(UInt64, UnsafeMutableRawPointer?) -> Void
			fileprivate init(_ consumer: @escaping (UInt64, UnsafeMutableRawPointer?) -> Void) {
				self.consumer = consumer
			}
		}
		
		/// C function pointer compatible with __cswiftslash_identified_list_ptr_f
		private static let consumerFunction:__cswiftslash_identified_list_iterator_f = { (key, ptr, ctx) in
			let context = Unmanaged<ConsumerContext>.fromOpaque(ctx).takeUnretainedValue()
			context.consumer(key, ptr)
		}
	}

	// MARK: - Test Cases
	@Test("__cswiftslash_identified_list :: initialization and deallocation")
	func testAtomicListInitialization() async {
		let list = IdentifiedListHarness()
		await list.close()
	}

	@Test("__cswiftslash_identified_list :: insert and remove single element")
	func testInsertAndRemoveSingleElement() async {
		let list = IdentifiedListHarness()
		
		let data = UnsafeMutableRawPointer(bitPattern: 0x1)!
		let key = await list.insert(data)
		
		let removedData = await list.remove(key: key)
		#expect(removedData == data)
		
		// ensure the element is no longer in the list
		let removedDataAgain = await list.remove(key: key)
		#expect(removedDataAgain == nil)
		
		// close the list
		await list.close()
	}

	@Test("__cswiftslash_identified_list :: insert multiple elements")
	func testInsertMultipleElements() async {
		let list = IdentifiedListHarness()
		
		var keys: [UInt64] = []
		let dataPointers = (1...100).map { UnsafeMutableRawPointer(bitPattern: $0)! }
		var keysAndData:[(UInt64, UnsafeMutableRawPointer)] = []

		// insert elements
		for data in dataPointers {
			let key = await list.insert(data)
			keys.append(key)
			#expect(key != 0)
			keysAndData.append((key, data))
		}
		
		// verify that all keys are unique
		#expect(Set(keys).count == keys.count)
		
		// close the list and deallocate any remaining elements
		await list.close { (k, ptr) in
			#expect(keys.contains(k))
			#expect(dataPointers.contains(where: { $0 == ptr }))
			#expect(keysAndData.contains(where: { $0.0 == k && $0.1 == ptr }))
		}
	}
	
	@Test("__cswiftslash_identified_list :: close list with consumer function")
	func testCloseListWithConsumer() async {
		let list = IdentifiedListHarness()
		
		let dataPointers = (1...5).map { UnsafeMutableRawPointer(bitPattern: $0)! }
		for data in dataPointers {
			_ = await list.insert(data)
		}
		
		var collectedKeys:[UInt64] = []
		var collectedData:[UnsafeMutableRawPointer?] = []
		await list.close { (key, ptr) in
			collectedKeys.append(key)
			collectedData.append(ptr)
		}
		
		// verify that all elements were processed during close
		#expect(collectedData.count == 5)
		#expect(Set(dataPointers) == Set(collectedData))
	}
	
	@Test("__cswiftslash_identified_list :: remove non-existent key")
	func testRemoveNonExistentKey() async {
		let list = IdentifiedListHarness()
		
		let data = UnsafeMutableRawPointer(bitPattern: 0x1)!
		let key = await list.insert(data)
		#expect(key != 0)
		
		// attempt to remove a key that doesn't exist
		let removedData = await list.remove(key: key + 1)
		#expect(removedData == nil)
		
		// clean up
		_ = await list.remove(key: key)
		await list.close()
	}

	@Test("__cswiftslash_identified_list :: concurrent insertions and removals")
	func testConcurrentInsertionsAndRemovals() async {
		let list = IdentifiedListHarness()
		let totalOperations = 100000
		let keyManager = KeyManager()
		
		for i in 0..<totalOperations {
			await withTaskGroup(of: Void.self) { group in
				group.addTask {
					let data = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
					data.storeBytes(of: UInt8(i % 256), as: UInt8.self)
					let key = await list.insert(data)
					await keyManager.addKey(key)
				}
				if i > 100 {
					let removedKey = await keyManager.removeRandomKey()
					group.addTask { [rk = removedKey] in
						if let key = rk {
							if let data = await list.remove(key: key) {
								data.deallocate()
							}
						}
					}
				}
				await group.waitForAll()
			}
		}
		
		// close the list
		var foundKeys = Set<UInt64>()
		await list.close(consumer:{ (k, ptr) in
			foundKeys.insert(k)
			ptr?.deallocate()
		})

		// verify that all keys were processed
		let keys = await keyManager.auditKeys()
		#expect(Set(keys) == foundKeys)
		#expect(foundKeys.count == 101)
	}

	@Test("__cswiftslash_identified_list :: fuzz testing")
	func testFuzzTestingAtomicList() async {
		let list = IdentifiedListHarness()
		let iterations = 10000
		let keyManager = KeyManager()
		for _ in 0..<iterations {
			let action = Int.random(in: 0...2)
			switch action {
				case 0:
					let data = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
					data.storeBytes(of: UInt8.random(in: 0...255), as: UInt8.self)
					let key = await list.insert(data)
					await keyManager.addKey(key)
				case 1:
					if let key = await keyManager.removeRandomKey() {
						if let data = await list.remove(key: key) {
							data.deallocate()
						}
					}
				case 2:
					var foundKeys = Set<UInt64>()
					await list.iterate { (k, d) in
						foundKeys.insert(k)
					}
					let keys = await keyManager.auditKeys()
					#expect(Set(keys) == foundKeys)
				default:
					break
			}
		}
		
		// clean up remaining elements
		await list.iterate { (_, ptr) in
			ptr?.deallocate()
		}
		
		// close the list
		await list.close()
	}
	
	@Test("__cswiftslash_identified_list :: iterate over elements")
	func testIterateOverElements() async {
		let list = IdentifiedListHarness()
		
		var keys:[UInt64] = []
		let dataPointers = (1...10).map { UnsafeMutableRawPointer(bitPattern: $0)! }
		
		// insert elements
		for data in dataPointers {
			let key = await list.insert(data)
			keys.append(key)
			#expect(key != 0)
		}
		
		// collect elements during iteration
		var iteratedKeys:[UInt64] = []
		var iteratedData:[UnsafeMutableRawPointer?] = []
		
		await list.iterate { (key, ptr) in
			iteratedKeys.append(key)
			iteratedData.append(ptr)
		}
		
		// verify all elements were iterated over
		#expect(Set(keys) == Set(iteratedKeys))
		#expect(Set(dataPointers) == Set(iteratedData.compactMap { $0 }))
		
		// clean up
		await list.close()
	}

	@Test("__cswiftslash_identified_list :: stress test with large number of elements")
	func testStressTestLargeNumberOfElements() async {
		let list = IdentifiedListHarness()
		let numberOfElements = 100_000
		var keys: [UInt64] = []
		// insert a large number of elements
		for i in 0..<numberOfElements {
			let data = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
			data.storeBytes(of: UInt8(i % 256), as: UInt8.self)
			let key = await list.insert(data)
			keys.append(key)
			#expect(key != 0)
		}

		// verify that all the keys have been inserted
		var foundKeys:Set<UInt64> = []
		await list.iterate { (k, _) in
			foundKeys.insert(k)
		}
		#expect(Set(keys) == foundKeys)
		
		// remove 10% of the elements
		let keysToRemove = keys[0..<numberOfElements/10]
		var removedKeys:Set<UInt64> = []
		for key in keysToRemove {
			if let data = await list.remove(key: key) {
				data.deallocate()
				removedKeys.insert(key)
			}
		}
		#expect(removedKeys.count == keysToRemove.count)
		
		// verify that all the keys have been removed
		var remainingKeys:Set<UInt64> = []
		await list.iterate { (k, _) in
			remainingKeys.insert(k)
		}
		#expect(remainingKeys.isDisjoint(with: removedKeys))
		#expect(remainingKeys.count == numberOfElements - keysToRemove.count)

		// remove the remaining elements
		var removedKeys2:Set<UInt64> = []
		for key in remainingKeys {
			if let data = await list.remove(key: key) {
				data.deallocate()
				removedKeys2.insert(key)
			}
		}
		#expect(removedKeys2 == remainingKeys)

		// verify that all the keys have been removed
		var finalKeys:Set<UInt64> = []
		await list.iterate { (k, _) in
			finalKeys.insert(k)
		}
		#expect(finalKeys.isEmpty)
		
		// close the list
		await list.close()
	}

	@Test("__cswiftslash_identified_list :: insert and remove same element multiple times")
	func testInsertRemoveSameElementMultipleTimes() async {
		let list = IdentifiedListHarness()
		let data = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
		data.storeBytes(of: UInt8(42), as: UInt8.self)
		
		for _ in 0..<100 {
			let key = await list.insert(data)
			#expect(key != 0)
			let removedData = await list.remove(key: key)
			#expect(removedData == data)
		}
		
		// clean up
		data.deallocate()
		await list.close()
	}
}