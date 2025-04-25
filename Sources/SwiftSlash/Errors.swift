public struct InternalLaunchError:Swift.Error {}

public enum WrittenDataChannelClosureError:Swift.Error {
    /// thrown when the child process closes the reading file handle that the current process is writing to.
    case dataChannelClosed
    /// thrown when the operating system throws an error when attempting to write data.
    case systemWriteErrorThrown(Swift.Error)
    /// thrown when the write loop task is cancelled
    case writeLoopTaskCancelled
}

/// the type of error that is thrown when there is a problem calling waitpid
public struct WaitPIDError:Swift.Error {
	/// the corresponding errno value returned by the system for this error.
    public let errnoValue:Int32
}

/// describes an error in the process spawning function. these are generally considered to be errors that can be thrown after the child process has been launched but before it has finished configuring itself for the specified work.
public enum ProcessSpawnError:UInt8, Swift.Error {
	/// describes a failure to change the working directory of the child process.
	case chdirFailure = 0xAA
	/// describes a failure to clear the environment variables of the child process.
	case envClearFailure = 0xBA
	/// describes a failure to set the environment variables of the child process.
	case envSetFailure = 0xBB
	/// describes a failure to assign the reading end of a pipe to the child process.
	case dup2ReaderFailure = 0xCA
	/// describes a failure to close redundant reading pipe file handles after they have been successfully dup2'd to the running process.
	case readerPipeCleanupFailure = 0xCB
	/// describes a failure to assign the writing end of a pipe to the child process.
	case dup2WriterFailure = 0xCC
	/// describes a failure to close redundant writing pipes file handles after they have been successfully dup2'd to the running process.
	case writerPipeCleanupFailure = 0xCD
	/// describes a failure to open the system's directory of file handles.
	case fhCleanupDirOpenFailure = 0xDA
	/// describes a failure to close a file handle.
	case fhCleanupCloseFailure = 0xDB
	/// describes a failure to close the system's directory of file handles.
	case fhCleanupDirCloseFailure = 0xDC
	/// describes a failure to create the internal posix pipe that is used to facilitate the logistics between the parent and child process
	case posixPipeCreateFailure = 0xEA
	/// describes a failure to complete the initial clean up of the internal posix pipe that is used to facilitate the logistics between the parent and child process
	case posixPipeInitialCleanupFailure = 0xEB
	/// describes a failure to complete the final clean up of the internal posix pipe that is used to facilitate the logistics between the parent and child process
	case posixPipeFinalCleanupFailure = 0xEC
	/// describes an internal failure of the spawn function
	case internalFailure = 0xFA
	/// describes a failure of the fork function
	case forkFailure = 0xFB
}