/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

/// a shell command to run.
public struct Command:Sendable {
	
	/// the executable command to run. this should be an absolute path.
	public var executable:Path
	/// the arguments to pass to the command.
	public var arguments:[String]
	/// the environment variables to set for the command.
	public var environment:[String:String]
	/// the working directory to run the command in.
	public var workingDirectory:Path

	/// creates a new command.
	/// - parameters:
	///		- execute: the absolute path to execute.
	///		- arguments: the arguments to pass to the executed command. default value: no arguments.
	///		- environment: the environment variables to set for the command. default vaule: no environment variables.
	///		- workingDirectory: the working directory to run the command in. default value: the current working directory of the launching process.
	public init(
		absolutePath execute:consuming Path,
		arguments args:consuming [String] = [],
		environment envs:consuming [String:String] = [:],
		workingDirectory wd:consuming Path = CurrentProcess.workingDirectory()
	) {
		executable = execute
		arguments = args
		environment = envs
		workingDirectory = wd
	}

	/// creates a new command with a relative executable name.
	/// - parameters:
	///		- execute: name of the command to execute. this name will be searched for in the PATH environment variable.
	public init(
		_ execute:consuming String,
		arguments args:consuming [String] = [],
		environment envs:consuming [String:String] = [:],
		workingDirectory wd:consuming Path = CurrentProcess.workingDirectory()
	) throws(PathSearchError) {
		executable = try CurrentProcess.searchPaths(executableName:execute)
		arguments = args
		environment = envs
		workingDirectory = wd
	}

	/// mutate the configured environment variables to match the environment of the current process at the time of calling.
	public mutating func inheritCurrentEnvironment() {
		environment = CurrentProcess.environmentVariables()
	}
}

extension Command:Hashable, Equatable {
	/// equality operator for Command.
	public static func == (lhs:Command, rhs:Command) -> Bool {
		return lhs.executable == rhs.executable && lhs.arguments == rhs.arguments && lhs.environment == rhs.environment && lhs.workingDirectory == rhs.workingDirectory
	}
	/// hash function for Command.
	public func hash(into hasher:inout Hasher) {
		hasher.combine(executable)
		hasher.combine(arguments)
		hasher.combine(environment)
		hasher.combine(workingDirectory)
	}
}