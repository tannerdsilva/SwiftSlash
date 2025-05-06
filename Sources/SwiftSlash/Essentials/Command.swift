/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

/// Defines a fully-configured external process (executable, arguments, environment, and working directory) as a launch plan—without performing execution itself.
public struct Command:Sendable {
	
	/// The executable command to run. this should be an absolute path.
	public var executable:Path
	/// The arguments to pass to the command.
	public var arguments:[String]
	/// The environment variables to set for the command.
	public var environment:[String:String]
	/// The working directory to run the command in.
	public var workingDirectory:Path

	/// Creates a new command.
	/// - Parameters:
	/// 	- execute: the absolute path to the executable to run.
	/// 	- args: the arguments to pass to the executed command. default value: no arguments.
	/// 	- envs: the environment variables to set for the command. default vaule: no environment variables.
	/// 	- wd: the working directory to run the command in. default value: the current working directory of the launching process.
	public init(
		absolutePath execute:consuming Path,
		arguments args:consuming [String] = [],
		environment envs:consuming [String:String] = [:],
		workingDirectory wd:consuming Path = CurrentEnvironment.workingDirectory()
	) {
		executable = execute
		arguments = args
		environment = envs
		workingDirectory = wd
	}

	/// Creates a new command with a relative executable name. This will search the PATH environment variable for the executable.
	/// - Parameters:
	/// 	- executeRelativeName: name of the command to execute. this name will be searched for in the PATH environment variable.
	/// 	- args: the arguments to pass to the executed command. default value: no arguments.
	/// 	- envs: the environment variables to set for the command. default vaule: no environment variables.
	/// 	- wd: the working directory to run the command in. *Default value*: the current working directory of the launching process.
	/// - Throws: PathSearchError if the executable cannot be found in the `PATH` environment variable.
	public init(
		_ executeRelativeName:consuming String,
		arguments args:consuming [String] = [],
		environment envs:consuming [String:String] = [:],
		workingDirectory wd:consuming Path = CurrentEnvironment.workingDirectory()
	) throws(CurrentEnvironment.PathSearchError) {
		executable = try CurrentEnvironment.searchPaths(executableName:executeRelativeName)
		arguments = args
		environment = envs
		workingDirectory = wd
	}

	/// Initialize a new command based on a shell command string. The command will be executed using shell found at `/bin/sh`.
	/// - Parameters:
	/// 	- shCommand: the shell command to run on the `sh` shell.
	/// 	- envs: the environment variables to set for the command. *Default value*: no environment values.
	/// 	- wd: The working directory to run the command in. *Default value*: 
	public init(
		sh shCommand:consuming String, 
		environment envs:consuming [String:String],
		workingDirectory wd:consuming Path = CurrentEnvironment.workingDirectory()
	) {
		executable = "/bin/sh"
		arguments = ["-c", shCommand]
		environment = envs
		workingDirectory = wd
	}

	/// Mutate the current instance to mirror the environment variables of the calling process.
	public mutating func inheritCurrentEnvironment() {
		environment = CurrentEnvironment.environmentVariables()
	}
	
	/// Encapsulates the result of a Command that was run using the convenience function ``SwiftSlash/Command/runSync()`.
	public struct SyncResult:Sendable {
		/// The exit code of the process.
		let exit:ChildProcess.Exit
		/// The data that was written to `STDERR` while the child process was running.
		let stderr:[[UInt8]]
		/// The data that was written to `STDOUT` while the child process was running.
		let stdout:[[UInt8]]
		/// A convenience boolean that is set to `true` when `exit == .code(0)`
		let succeeded:Bool
	}
	
	/// Run a command synchronously.
	public func runSync() async throws -> SyncResult {
		enum StandardOutputVariant {
			case stdout([[UInt8]])
			case stderr([[UInt8]])
		}
		let processInterface = ChildProcess(self)
		return try await withThrowingTaskGroup(of:StandardOutputVariant.self, returning:SyncResult.self) { [pi = processInterface] tg in
			tg.addTask { [stdoutStream = pi.stdout] in
				var buildLines = [[UInt8]]()
				for await nextLine in stdoutStream {
					buildLines.append(contentsOf:nextLine)
				}
				return .stdout(buildLines)
			}
			
			tg.addTask { [stderrStream = pi.stderr] in
				var buildLines = [[UInt8]]()
				for await nextLine in stderrStream {
					buildLines.append(contentsOf:nextLine)
				}
				return .stderr(buildLines)
			}
			
			let exitResult = try await pi.run()
			var assembleOut = [[UInt8]]()
			var assembleErr = [[UInt8]]()
			for try await childTaskResult in tg {
				switch childTaskResult {
					case .stderr(let err):
						assembleErr = err
					case .stdout(let out):
						assembleOut = out
				}
			}
			let isSuccessful:Bool
			switch exitResult {
				case .code(let exitValue):
					isSuccessful = true
				default:
					isSuccessful = false
			}
			return SyncResult(exit:exitResult, stderr:assembleErr, stdout:assembleOut, succeeded:isSuccessful)
		}
	}
}

extension Command:Hashable, Equatable {
	public static func == (lhs:Command, rhs:Command) -> Bool {
		return lhs.executable == rhs.executable && lhs.arguments == rhs.arguments && lhs.environment == rhs.environment && lhs.workingDirectory == rhs.workingDirectory
	}
	public func hash(into hasher:inout Hasher) {
		hasher.combine(executable)
		hasher.combine(arguments)
		hasher.combine(environment)
		hasher.combine(workingDirectory)
	}
}
