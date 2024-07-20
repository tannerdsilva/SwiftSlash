import __cswiftslash
import SwiftSlashContained

/// atomiclist is a thread-safe and reentrancy-safe class that captures instances of swift types and allows them to be stored an accessed by an arbitrary key value.
internal final class AtomicList<T>:@unchecked Sendable {
	private let list_store_ptr:UnsafeMutablePointer<_cswiftslash_identified_list_pair_t>
	
	deinit {
		_cswiftslash_identified_list_close(list_store_ptr, { key, ptr in
			_ = Unmanaged<Contained<T>>.fromOpaque(ptr).takeRetainedValue()
		})
		list_store_ptr.deinitialize(count:1).deallocate()
	}

	internal init() {
		self.list_store_ptr = UnsafeMutablePointer<_cswiftslash_identified_list_pair_t>.allocate(capacity:1)
		self.list_store_ptr.initialize(to:_cswiftslash_identified_list_init())
	}

	internal func forEach(_ body:(UInt64, T) -> Void) {
		withoutActuallyEscaping(body, do: { bodyEsc in
			_cswiftslash_identified_list_iterate(list_store_ptr, { key, ptr in
				let um = Unmanaged<Contained<T>>.fromOpaque(ptr)
				bodyEsc(key, um.takeUnretainedValue().value())
			})
		})
	}

	internal func insert(_ data:T) -> UInt64 {
		return _cswiftslash_identified_list_insert(list_store_ptr, Unmanaged.passRetained(Contained(data)).toOpaque())
	}

	@discardableResult internal func remove(_ key:UInt64) -> T? {
		switch (_cswiftslash_identified_list_remove(list_store_ptr, key)) {
			case .some(let contained):
				return Unmanaged<Contained<T>>.fromOpaque(contained).takeRetainedValue().value()
			case .none:
				return nil
		}
	}
}