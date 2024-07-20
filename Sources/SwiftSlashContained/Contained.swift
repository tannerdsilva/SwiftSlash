/// a container class that allows for storage and retrieval of a contained value.
public final class Contained<A> {
	private var val:A
	public init(_ arg:A) {
		self.val = arg
	}
	public borrowing func value() -> A {
		return val
	}
}
