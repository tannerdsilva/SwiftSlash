/// thrown when the system polling facility fails to operate as expected.
public struct SystemPollingError:Swift.Error {

	/// the error code that was returned by the system.
	public let code:Int32

	/// the human friendly message that the system provides for the error code.
	public let message:String
}
