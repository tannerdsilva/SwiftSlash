import struct Foundation.Data
import struct Foundation.URL

// Defines a command that is to be executed.
public struct Command {
    /// Contains the result of a `Command` that has run synchronously
    public struct Result {
        /// A convenience boolean that is set to `true` when `exitCode` is `0`
        public let succeeded:Bool
		/// The exit code of the process
        public let exitCode:Int32
		/// The data that was written to `STDOUT` by the process.
        public let stdout:[Data]
		/// The data that was written to `STDERR` by the process.
        public let stderr:[Data]
        
        internal init(exitCode:Int32, stdout:[Data], stderr:[Data]) {
            self.exitCode = exitCode
            self.stdout = stdout
            self.stderr = stderr
            if exitCode == 0 {
                self.succeeded = true
            } else {
                self.succeeded = false
            }
        }
    }
	
	/// Absolute path to the executable that will be run.
	public var executable:String
	/// The arguments that will be passed to the executable
	public var arguments:[String]
	/// The environment variables that will be assigned before the process begins running.
	public var environment:[String:String]
	/// The working directory that the process will have when it is launched
    public var workingDirectory:URL
    
    /// Initialize with an executable path and arguments. This initializer will run the executable directly without a shell.
    /// - Parameters:
    /// 	- execute: The absolute path to the executable to run.
    /// 	- arguments: An array of arguments to pass into the executable.
	/// 	- environment: The environment variables that will be assigned before the process begins running.
	/// 	- workingDirectory: The working directory that the process will have when it is launched.
	public init(absolutePath execute:String,
				arguments:[String] = [String](),
				environment:[String:String] = CurrentProcessState.getCurrentEnvironmentVariables(),
				workingDirectory:URL = CurrentProcessState.getCurrentWorkingDirectory()) {
		self.executable = execute
		self.arguments = arguments	
		self.environment = environment
		self.workingDirectory = workingDirectory
	}
    
	/// Initialize with an executable name and arguments.
	/// - This initializer does __not__ use a system shell to launch the work.
	/// - Parameters:
	/// 	- execute: Either an implied name or absolute pathname of the executable to run.
	/// 		- If an implied name (ex: `ifconfig`), the current `PATH`'s will be searched for the absolute path of the executable.
	/// 		- If an absolute path (ex: `/sbin/ifconfig`), the executable at that path will be run.
	/// 			- Input for this parameter will only be considered an absolute path if it begins with an `/`.
	/// 	- arguments: An array of arguments to pass to the executable.
	/// 	- environment: The environment variables that will be assigned before the process begins running.
	/// 	- workingDirectory: The working directory that the process will have when it is launched.
	/// - Throws: ``SwiftSlash/Error/PathSearch`` if the executable cannot be found in the current `PATH`.
	public init(_ execute:String,
				arguments:[String] = [String](),
				environment:[String:String] = CurrentProcessState.getCurrentEnvironmentVariables(),
				workingDirectory:URL = CurrentProcessState.getCurrentWorkingDirectory()) throws {
		if execute.hasPrefix("/") {
			// if the executable is an absolute path, use it directly
			self.executable = execute
		} else {
			// if the executable is an implied name, search the PATH's for the executable
			self.executable = try CurrentProcessState.searchCurrentPathsForExecutable(execute)
		}
		self.arguments = arguments
		self.environment = environment
		self.workingDirectory = workingDirectory
	}
    
    /// Run a command synchronously.
    /// - Returns: Results of the command are captured in a ``Result`` and returned after the command has finished executing
    public func runSync() async throws -> Command.Result {
		let procInterface = ProcessInterface(command:self)
		try await procInterface.launch()
		//add the stdout task
		var outLines = [Data]()
		for await line in await procInterface.stdout {
			outLines.append(line)
		}

		//add the stderr task
		var errLines = [Data]()
		for await line in await procInterface.stderr {
			errLines.append(line)
		}
		let exitCode = try await procInterface.exitCode()
		return Result(exitCode:exitCode, stdout:outLines, stderr:errLines)
	}
}

// MARK: - Bash and Zsh Initializers
extension Command {
	/// Initialize with a "command string" to pass into the Bash shell.
    /// - Parameters:
	/// 	- command: Command string that bash will run execute
	/// Notes:
	/// 	- This initializer will wrap the command through the `bash` shell.
	/// 	- This initializer assumes that the Bash shell is located at `/bin/bash`. If this is not the case, you should use the ``init(absolutePath:arguments:environment:workingDirectory:)`` initializer instead.
	public init(bash command:String,
				environment:[String:String] = CurrentProcessState.getCurrentEnvironmentVariables(),
				workingDirectory:URL = CurrentProcessState.getCurrentWorkingDirectory()) {
		self.executable = "/bin/bash"
		self.arguments = ["-c", command]
		self.environment = environment
		self.workingDirectory = workingDirectory
	}

	/// Initialize with a "command string" to pass into the Zsh shell.
	/// - Parameters:
	/// 	- command: Command string that zsh will run execute
	/// - Notes:
	/// 	- This initializer will wrap the command through the `zsh`` shell.
	/// 	- This initializer assumes that the Zsh shell is located at `/bin/zsh`. If this is not the case, you should use the ``init(absolutePath:arguments:environment:workingDirectory:)`` initializer instead.
	public init(zsh command:String,
				environment:[String:String] = CurrentProcessState.getCurrentEnvironmentVariables(),
				workingDirectory:URL = CurrentProcessState.getCurrentWorkingDirectory()) {
		self.executable = "/bin/zsh"
		self.arguments = ["-c", command]
		self.environment = environment
		self.workingDirectory = workingDirectory
	}
}
