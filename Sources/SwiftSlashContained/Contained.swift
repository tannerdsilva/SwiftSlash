/* LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

/// a container class that allows for storage and retrieval of a given swift type using reference semantics.
public final class Contained<ContainedType> {
	
	/// stores the value.
	private let val:ContainedType

	/// initialize a new instance of Contained, storing the given value.
	/// - parameter arg: the value to store.
	public init(_ arg:ContainedType) {
		self.val = arg
	}

	/// retrieve the stored value from this instance.
	/// - returns: the stored value.
	public borrowing func value() -> ContainedType {
		return val
	}
}