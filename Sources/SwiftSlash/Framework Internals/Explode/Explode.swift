import Foundation

fileprivate typealias CounterType = Int
extension Collection {
	//explode a collection - allows the user to handle the merging of data themselves
	internal func explode<T>(using thisFunction:@escaping (Int, Element) throws -> T?, merge mergeFunction:@escaping (Int, T) throws -> Void) {
		guard count > 0 else {
			return
		}

		//pre-processing access
		let enumerateQueue = DispatchQueue(label:"com.swiftslash.function.explode.enumerate", target:process_master_queue)
		var iterator = self.makeIterator()
		var i:CounterType = 0
		func getNext() -> (CounterType, Self.Element?) {
			return enumerateQueue.sync {
				defer {
					i += 1
				}
				return (i, iterator.next())
			}
		}

		//post-process merging
		let returnQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:process_master_queue)

		//process
		DispatchQueue.concurrentPerform(iterations:count) { _ in
			let iteratorFetch = getNext()
			let n = iteratorFetch.0
			if let thisItem = iteratorFetch.1, let returnedValue = try? thisFunction(n, thisItem) {
				returnQueue.sync {
					try? mergeFunction(n, returnedValue)
				}
			}
		}
	}
}