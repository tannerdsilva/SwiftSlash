/// a container class that allows for storage and retrieval of a given swift type.
public final class Contained<A> {
	/// stores the value.
	private var val:A

	/// initialize a new instance of Contained, storing the given value.
	public init(_ arg:A) {
		self.val = arg
	}

	/// retrieve the stored value from this instance.
	public borrowing func value() -> A {
		return val
	}
}
