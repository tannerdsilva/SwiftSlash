import __cswiftslash
import SwiftSlashContained

/// IdentifiedList is a thread-safe and reentrancy-safe class that captures instances of swift types and allows them to be stored an accessed by an individually identifiable key value.
public final class IdentifiedList<T>:@unchecked Sendable {
	// this is the private memory space for the list.
	private let list_store_ptr:UnsafeMutablePointer<_cswiftslash_identified_list_pair_t>
	
	deinit {
		_cswiftslash_identified_list_close(list_store_ptr, { key, ptr in
			_ = Unmanaged<Contained<T>>.fromOpaque(ptr).takeRetainedValue()
		})
		list_store_ptr.deallocate()
	}

	/// initialize a new IdentifiedList instance.
	public init() {
		self.list_store_ptr = UnsafeMutablePointer<_cswiftslash_identified_list_pair_t>.allocate(capacity:1)
		self.list_store_ptr.initialize(to:_cswiftslash_identified_list_init())
	}

	/// iterate synchronously over all elements in the list.
	public func forEach(_ body:(UInt64, T) -> Void) {
		withoutActuallyEscaping(body, do: { bodyEsc in
			_cswiftslash_identified_list_iterate(list_store_ptr, { key, ptr in
				bodyEsc(key, Unmanaged<Contained<T>>.fromOpaque(ptr).takeUnretainedValue().value())
			})
		})
	}

	/// insert a new element into the list.
	/// - parameter data: the data to insert into the list.
	/// - returns: the key that is associated with the data.
	public func insert(_ data:consuming T) -> UInt64 {
		return _cswiftslash_identified_list_insert(list_store_ptr, Unmanaged.passRetained(Contained(data)).toOpaque())
	}

	/// remove an element from the list.
	/// - parameter key: the key that is associated with the data.
	/// - returns: the data that was removed from the list.
	@discardableResult public func remove(_ key:UInt64) -> T? {
		switch (_cswiftslash_identified_list_remove(list_store_ptr, key)) {
			case .some(let contained):
				return Unmanaged<Contained<T>>.fromOpaque(contained).takeRetainedValue().value()
			case .none:
				return nil
		}
	}
}