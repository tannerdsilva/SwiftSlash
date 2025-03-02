/* LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

/// represents a low level system error that is returned when a kernel-level system call fails.
public struct SystemErrno:Swift.Error {
	/// the error code that was returned by the system call.
	public let code:Int32
	/// create a new system error with the specified error code.
	public init(_ code:Int32) {
		self.code = code
	}
}