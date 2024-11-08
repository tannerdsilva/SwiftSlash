/// represents a pthread worker that takes a function as an argument, runs passed work function, and returns the result. if an error is thrown within the work function, it is returned as a failure.
public struct GenericPThread<R:Sendable>:PThreadWork {
	/// function to run.
	private let funcToRun:Argument

	/// the argument type for the function to run.
	public typealias Argument = @Sendable () throws -> R
	/// the return type for the function to run.
	public typealias ReturnType = R

	/// creates a new instance of GenericPThread.
	/// - parameters:
	/// 	- argument: the function to run.
	public init(_ argument:@escaping Argument) {
		self.funcToRun = argument
	}

	/// runs the function and returns the result.
	/// - returns: the result of the function.
	/// - throws: any error that prevents the work from being completed.
	public mutating func pthreadWork() throws -> R {
		return try funcToRun()
	}
}
