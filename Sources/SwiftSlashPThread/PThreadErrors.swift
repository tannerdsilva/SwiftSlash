/// thrown when a pthread cannot be created.
internal struct LaunchFailure:Swift.Error {}

/// thrown when a pthread is unable to be canceled.
internal struct UnableToCancel:Swift.Error {}
