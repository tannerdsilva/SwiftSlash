/// represents a low level system error that is returned when a kernel-level system call fails.
public struct SystemErrno:Swift.Error {
	/// the error code that was returned by the system call.
	public let code:Int32
	/// create a new system error with the specified error code.
	public init(_ code:Int32) {
		self.code = code
	}
}