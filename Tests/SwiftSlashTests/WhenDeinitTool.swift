internal final class WhenDeinitTool<T> {
	private var deinitClosure: (() -> Void)?
	internal var value:T
	internal init(_ value:T, deinitClosure: @escaping () -> Void) {
		self.deinitClosure = deinitClosure
		self.value = value
	}
	
	deinit {
		deinitClosure?()
	}
}

extension WhenDeinitTool:Equatable, Hashable where T:Hashable, T:Equatable {
	static func == (lhs: WhenDeinitTool<T>, rhs: WhenDeinitTool<T>) -> Bool {
		return lhs.value == rhs.value
	}
	
	func hash(into hasher: inout Hasher) {
		hasher.combine(value)
	}
}
