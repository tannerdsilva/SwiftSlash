import Foundation
import Glibc

public struct Command:Hashable, Equatable {
	var executable:String
	var arguments:[String]
	var environment:[String:String] = CurrentProcessState.getCurrentEnvironmentVariables()
	var workingDirectory:URL = CurrentProcessState.getCurrentWorkingDirectory()
	public init?(command:String) {
		guard command.count > 0 else {
			return nil
		}
		var elements = command.split(separator:" ").compactMap { String($0) }
		guard elements.count > 1 else {
			return nil
		}
		self.executable = elements.removeFirst()
		self.arguments = elements
	}
	
	public init(execute:String) {
		self.executable = execute
		self.arguments = [String]()
	}
	
	public init(execute:String, arguments:[String]) {
		self.executable = execute
		self.arguments = arguments	
	}
	
	public init(bash command:String) {
		self.executable = "/bin/bash"
		self.arguments = ["-c", command]
	}
	
	public func runSync() async throws -> CommandResult {
		let procInterface = ProcessInterface(command:self)
		let exitCode = try await procInterface.exitCode()
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

		return CommandResult(exitCode:exitCode, stdout:outLines, stderr:errLines)
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

public struct CommandResult {
	public var succeeded:Bool {
		get {
			if exitCode == 0 {
				return true
			} else {
				return false
			}
		}
	}
	public let exitCode:Int32
	public let stdout:[Data]
	public let stderr:[Data]
    
    public init(exitCode:Int32, stdout:[Data], stderr:[Data]) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}
