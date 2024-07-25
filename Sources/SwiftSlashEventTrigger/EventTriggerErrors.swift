/// various errors that may be thrown by the EventTrigger subsystem
internal enum EventTriggerErrors:Swift.Error {
	
	/// thrown when a given file handle (for reading) is not able to register with an event trigger. this is considered an internal error that should never be thrown under any circumstances 
	case readerRegistrationFailure(Int32, Int32)

	/// thrown when a given file handle (for writing) is not able to register with an event trigger. this is considered an internal error that should never be thrown under any circumstances
	case writerRegistrationFailure(Int32, Int32)

	/// thrown when a given file handle (for reading) is not able to deregister with an event trigger. this is considered an internal error that should never be thrown under any circumstances
	case readerDeregistrationFailure(Int32, Int32)

	/// thrown when a given file handle (for writing) is not able to deregister with an event trigger. this is considered an internal error that should never be thrown under any circumstances
	case writerDeregistrationFailure(Int32, Int32)
}