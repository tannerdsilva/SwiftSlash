import __cswiftslash_identified_list
import SwiftSlashContained

/// IdentifiedList is a thread-safe and reentrancy-safe class that captures instances of swift types and allows them to be stored an accessed by an individually identifiable key value.
public final class IdentifiedList<T>:@unchecked Sendable {
	// this is the private memory space for the list.
	private let list_store_ptr:UnsafeMutablePointer<__cswiftslash_identified_list_pair_t>
	
	deinit {
		var allPtrs = [UnsafeMutableRawPointer]()
		withUnsafeMutablePointer(to: &allPtrs) { allPtrsPtr in
			__cswiftslash_identified_list_close(list_store_ptr, { key, ptr, ctx in
				ctx.assumingMemoryBound(to:[UnsafeMutableRawPointer].self).pointee.append(ptr)
			}, allPtrsPtr)
		}
		for ptr in allPtrs {
			_ = Unmanaged<Contained<T>>.fromOpaque(ptr).takeRetainedValue()
		}
		list_store_ptr.deallocate()
	}

	/// initialize a new IdentifiedList instance.
	public init() {
		list_store_ptr = UnsafeMutablePointer<__cswiftslash_identified_list_pair_t>.allocate(capacity:1)
		list_store_ptr.initialize(to:__cswiftslash_identified_list_init())
	}

	/// iterate synchronously over all elements in the list.
	public func forEach(_ body:(UInt64, T) -> Void) {
		var allPtrs:([UInt64], [UnsafeMutableRawPointer]) = ([UInt64](), [UnsafeMutableRawPointer]())
		withUnsafeMutablePointer(to: &allPtrs) { allPtrsPtr in
			__cswiftslash_identified_list_iterate(list_store_ptr, { key, ptr, ctx in
				ctx.assumingMemoryBound(to: ([UInt64], [UnsafeMutableRawPointer]).self).pointee.0.append(key)
				ctx.assumingMemoryBound(to: ([UInt64], [UnsafeMutableRawPointer]).self).pointee.1.append(ptr)
			}, allPtrsPtr, true)
		}
		for (i, ptr) in allPtrs.1.enumerated() {
			let contained = Unmanaged<Contained<T>>.fromOpaque(ptr).takeUnretainedValue()
			body(allPtrs.0[i], contained.value())
		}
		__cswiftslash_identified_list_iterate_hanginglock_complete(list_store_ptr)
	}

	/// insert a new element into the list.
	/// - parameter data: the data to insert into the list.
	/// - returns: the key that is associated with the data.
	public func insert(_ data:consuming T) -> UInt64 {
		return __cswiftslash_identified_list_insert(list_store_ptr, Unmanaged.passRetained(Contained(data)).toOpaque())
	}

	/// remove an element from the list.
	/// - parameter key: the key that is associated with the data.
	/// - returns: the data that was removed from the list.
	@discardableResult public func remove(_ key:UInt64) -> T? {
		switch (__cswiftslash_identified_list_remove(list_store_ptr, key)) {
			case .some(let contained):
				return Unmanaged<Contained<T>>.fromOpaque(contained).takeRetainedValue().value()
			case .none:
				return nil
		}
	}
}