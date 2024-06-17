import XCTest
@testable import SwiftSlash

class AtomicListTests: XCTestCase {
	func testMemoryLifecycle() {
		var atomicList:AtomicList<WhenDeinitTool<Int>>? = AtomicList<WhenDeinitTool<Int>>()

		var deinitCount = 0
		func didDeinit() {
			deinitCount += 1
		}
		
		// Insert elements
		let key1 = atomicList!.insert(WhenDeinitTool(10, deinitClosure: didDeinit))
		let key2 = atomicList!.insert(WhenDeinitTool(20, deinitClosure: didDeinit))
		let key3 = atomicList!.insert(WhenDeinitTool(30, deinitClosure: didDeinit))
		
		// Check if elements are inserted correctly
		var result: [UInt64:Int] = [:]
		atomicList!.forEach { k, value in
			result[k] = value.value
		}
		XCTAssertEqual(result, [key1: 10, key2: 20, key3: 30])
		
		// Remove an element
		let removedValue = atomicList!.remove(key2)?.value
		XCTAssertEqual(removedValue, 20)
		
		// Check if the removed element is no longer present
		result = [:]
		atomicList!.forEach { k, value in
			result[k] = value.value
		}
		XCTAssertEqual(result, [key1: 10, key3: 30])

		// Check if the deinit closure is called
		XCTAssertEqual(deinitCount, 1)

		// Deinitialize the atomic list
		atomicList = nil

		// Check if the deinit closure is called for the remaining elements
		XCTAssertEqual(deinitCount, 3)
	}
    
    func testRemoveNonExistingKey() {
        let atomicList = AtomicList<String>()
        
        // Try to remove a non-existing key
        let removedValue = atomicList.remove(123)
        XCTAssertNil(removedValue)
    }
    
    func testConcurrentInsertAndRemove() async {
        let atomicList = AtomicList<Int>()
        
		let keptItems = await withTaskGroup(of:Optional<(UInt64, Int)>.self, returning:[UInt64:Int].self) { tg in
			for index in 0..<100 {
				tg.addTask {
					let key = atomicList.insert(index)
					
					// Remove half of the elements
					if index % 2 == 0 {
						let removedValue = atomicList.remove(key)
						XCTAssertEqual(removedValue, index)
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

        // Check if the remaining elements are inserted correctly
        var result: [UInt64:Int] = [:]
        atomicList.forEach { k, value in
            result[k] = value
        }
        XCTAssertEqual(result, keptItems)
    }
}