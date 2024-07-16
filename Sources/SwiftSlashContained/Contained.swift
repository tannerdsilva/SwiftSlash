public final class Contained<A> {
	private var val:A
	public init(_ arg:A) {
		self.val = arg
	}
	public func accessContainedValue<R>(_ f:(UnsafeMutablePointer<A>) throws -> R) rethrows -> R {
		return try withUnsafeMutablePointer(to:&val) { ptr in
			return try f(ptr)
		}
	}
}
