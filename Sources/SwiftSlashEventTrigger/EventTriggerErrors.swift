/*
LICENSE MIT
copyright (c) tanner silva 2026. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

/// various errors that may be thrown by the EventTrigger subsystem
public enum EventTriggerErrors:Swift.Error {
	
	/// thrown when a given file handle (for reading) is not able to register with an event trigger. this is considered an internal error that should never be thrown under any circumstances 
	case readerRegistrationFailure(Int32, Int32)

	/// thrown when a given file handle (for writing) is not able to register with an event trigger. this is considered an internal error that should never be thrown under any circumstances
	case writerRegistrationFailure(Int32, Int32)

	/// thrown when a given file handle (for reading) is not able to deregister with an event trigger. this is considered an internal error that should never be thrown under any circumstances
	case readerDeregistrationFailure(Int32, Int32)

	/// thrown when a given file handle (for writing) is not able to deregister with an event trigger. this is considered an internal error that should never be thrown under any circumstances
	case writerDeregistrationFailure(Int32, Int32)

	/// thrown when a given process is not able to register its exit monitor with an event trigger. on Linux this can be thrown when pidfd support is unavailable (kernels older than 5.3).
	case processRegistrationFailure(Int32, Int32)

	/// thrown when a given process is not able to deregister its exit monitor with an event trigger. this is considered an internal error that should never be thrown under any circumstances
	case processDeregistrationFailure(Int32, Int32)
}