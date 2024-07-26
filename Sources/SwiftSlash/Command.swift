public struct Command {
	
	/// the executable command to run. this should be an absolute path.
	public var executable:String
	/// the arguments to pass to the command.
	public var arguments:[String]
	/// the environment variables to set for the command.
	public var environment:[String:String]
	/// the working directory to run the command in.
	public var workingDirectory:String

	/// creates a new command.
	/// - parameters:
	///		- execute: the absolute path to execute.
	///		- arguments: the arguments to pass to the executed command. default value: no arguments.
	///		- environment: the environment variables to set for the command. default vaule: no environment variables.
	///		- workingDirectory: the working directory to run the command in. default value: the current working directory of the launching process.
	public init(
		absolutePath execute:String,
		arguments:[String] = [],
		environment:[String:String] = [:],
		workingDirectory:String = CurrentProcess.workingDirectory()
	) {
		executable = execute
		self.arguments = arguments
		self.environment = environment
		self.workingDirectory = workingDirectory
	}

	/// creates a new command with a relative executable name.
	/// - parameters:
	///		- execute: the relative path to execute.
	public init(
		_ execute:String,
		arguments:[String] = [],
		environment:[String:String] = [:],
		workingDirectory:String = CurrentProcess.workingDirectory()
	) {
		executable = execute
		self.arguments = arguments
		self.environment = environment
		self.workingDirectory = workingDirectory
	}
}