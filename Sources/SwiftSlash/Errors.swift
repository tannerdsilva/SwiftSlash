/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

/// The type of error that is thrown when there is a problem calling waitpid.
public struct WaitPIDError:Swift.Error {
	/// The corresponding errno value returned by the system for this error.
	public let errnoValue:Int32
}

/// Describes an error in the process spawning function. These are generally considered to be errors that can be thrown after the child process has been launched but before it has finished configuring itself for the specified work.
public enum ProcessSpawnError:UInt8, Swift.Error {
	/// Thrown when the specified command is not a valid executable that can be run as a child process.
	case execSafetyCheckFailure = 0x00
	/// Describes a failure to change the working directory of the child process.
	case chdirFailure = 0xAA
	/// Describes a failure to clear the environment variables of the child process.
	case envClearFailure = 0xBA
	/// Describes a failure to set the environment variables of the child process.
	case envSetFailure = 0xBB
	/// Describes a failure to assign the reading end of a pipe to the child process.
	case dup2ReaderFailure = 0xCA
	/// Describes a failure to close redundant reading pipe file handles after they have been successfully dup2'd to the running process.
	case readerPipeCleanupFailure = 0xCB
	/// Describes a failure to assign the writing end of a pipe to the child process.
	case dup2WriterFailure = 0xCC
	/// Describes a failure to close redundant writing pipes file handles after they have been successfully dup2'd to the running process.
	case writerPipeCleanupFailure = 0xCD
	/// Describes a failure to open the system's directory of file handles.
	case fhCleanupDirOpenFailure = 0xDA
	/// Describes a failure to close a file handle.
	case fhCleanupCloseFailure = 0xDB
	/// Describes a failure to close the system's directory of file handles.
	case fhCleanupDirCloseFailure = 0xDC
	/// Describes a failure to create the internal posix pipe that is used to facilitate the logistics between the parent and child process.
	case posixPipeCreateFailure = 0xEA
	/// Describes a failure to complete the initial clean up of the internal posix pipe that is used to facilitate the logistics between the parent and child process.
	case posixPipeInitialCleanupFailure = 0xEB
	/// Describes a failure to complete the final clean up of the internal posix pipe that is used to facilitate the logistics between the parent and child process.
	case posixPipeFinalCleanupFailure = 0xEC
	/// describes an internal failure of the spawn function.
	case internalFailure = 0xFA
	/// describes a failure of the fork function.
	case forkFailure = 0xFB
}