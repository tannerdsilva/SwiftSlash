import __cswiftslash

/// atomiclist is a thread-safe and reentrancy-safe class that stores arbitrary instances of swift types and allows them to be stored an accessed by an arbitrary key value.
/// - note: AtomicList<T> is an unchecked sendable because the Swift compiler does not see C types as sendable. also, UnsafeMutablePointer does not want to classify as sendable, it is recommended that developers use unchecked sendable instead.
internal final class AtomicList<T>:@unchecked Sendable {
	private let list_store_ptr:UnsafeMutablePointer<_cswiftslash_identified_list_pair_t>
	
	deinit {
		_cswiftslash_identified_list_close(list_store_ptr, { key, ptr in
			Unmanaged<Contained>.fromOpaque(ptr).release()
		})
		list_store_ptr.deallocate()
	}

	internal init() {
		self.list_store_ptr = UnsafeMutablePointer<_cswiftslash_identified_list_pair_t>.allocate(capacity: 1)
		self.list_store_ptr.initialize(to:_cswiftslash_identified_list_init())
	}

	private final class Contained {
		private let store:T
		fileprivate init(store:T) {
			self.store = store
		}
		fileprivate func takeStored() -> T {
			return store
		}
	}

	internal func forEach(_ body:(UInt64, T) -> Void) {
		withoutActuallyEscaping(body, do: { bodyEsc in
			_cswiftslash_identified_list_iterate(list_store_ptr, { key, ptr in
				let um = Unmanaged<Contained>.fromOpaque(ptr)
				bodyEsc(key, um.takeUnretainedValue().takeStored())
			})
		})
	}

	internal func insert(_ data:T) -> UInt64 {
		return _cswiftslash_identified_list_insert(list_store_ptr, Unmanaged.passRetained(Contained(store:data)).toOpaque())
	}

	@discardableResult internal func remove(_ key:UInt64) -> T? {
		switch (_cswiftslash_identified_list_remove(list_store_ptr, key)) {
			case .some(let contained):
				return Unmanaged<Contained>.fromOpaque(contained).takeRetainedValue().takeStored()
			case .none:
				return nil
		}
	}
}