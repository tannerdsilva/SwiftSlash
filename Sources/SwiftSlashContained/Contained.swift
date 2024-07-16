public final class Contained<A> {
	private let val:A
	public init(_ arg:A) {
		self.val = arg
	}
	public consuming func consumeValue() -> A {
		return val
	}
}
