import Foundation

/// Defines a command that is to be executed.
public struct Command:Hashable, Equatable {
    /// Contains the result of a `Command` that has run synchronously
    public struct Result {
        /// A convenience boolean that is set to `true` when `exitCode` is set to `0`
        public let succeeded:Bool
        public let exitCode:Int32
        public let stdout:[Data]
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

	public var executable:String
	public var arguments:[String]
	public var environment:[String:String] = CurrentProcessState.getCurrentEnvironmentVariables()
    public var workingDirectory:URL = CurrentProcessState.getCurrentWorkingDirectory()
    
    /// Initialize from a string-encoded command, with spaces separating the arguments.
    /// - Parameter command: A string representing an executable (and optionally, the arguments following the executable) that you would like to run. Arguments separated by space
	public init(_ command:String) {
		guard command.count > 0 else {
			fatalError("cannot cannot initialize with a string of zero length")
		}
		var elements = command.split(separator:" ").compactMap { String($0) }
		guard elements.count >= 1 else {
			fatalError("could not parse executable")
		}
		self.executable = elements.removeFirst()
		self.arguments = elements
	}
    
    /// Initialize with an executable path and arguments
    /// - Parameters:
    ///   - execute: The path to the executable which shall be run
    ///   - arguments: An array of arguments to pass into the executable
	public init(execute:String, arguments:[String] = [String]()) {
		self.executable = execute
		self.arguments = arguments	
	}
    
    /// Initialize with a command to pass into the Bash shell
    /// - Parameter command: Command string that bash will run
	public init(bash command:String) {
		self.executable = "/bin/bash"
		self.arguments = ["-c", command]
	}
    
    /// Run a command synchronously
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
	
	public static func == (lhs:Command, rhs:Command) -> Bool {
		return (lhs.executable == rhs.executable) && (lhs.arguments == rhs.arguments) && (lhs.environment == rhs.environment)
	}
	
	public func hash(into hasher:inout Hasher) {
		hasher.combine(executable)
		hasher.combine(arguments)
		hasher.combine(environment)
	}
}
