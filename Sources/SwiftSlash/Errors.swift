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
    public let errnoValue:Int32
}