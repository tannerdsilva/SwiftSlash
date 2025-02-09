import Testing

internal final class WhenDeinitTool<T> {
	private let conf:Confirmation
	internal var value:T
	internal init(_ value:T, _ conf: Confirmation) {
		self.conf = conf
		self.value = value
	}
	
	deinit {
		conf.confirm()
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
