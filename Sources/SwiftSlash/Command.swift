import Foundation
import Glibc

public struct Command:Hashable, Equatable {
	var executable:String
	var arguments:[String]
	var environment:[String:String] = CurrentProcessState.getCurrentEnvironmentVariables()
	
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
	
	public init(bash command:String) {
		let commandTerminate = command.replacingOccurrences(of:"'", with:"''")
		self.executable = "/bin/bash"
		self.arguments = ["-c", commandTerminate]
	}
	
	public func runSync() throws -> CommandResult {
		let procInterface = ProcessInterface(command:self)
		var stdoutLines = [Data]()
		var stderrLines = [Data]()
		procInterface.stderrHandler = { data in
			stderrLines.append(data)
		}
		procInterface.stdoutHandler = { data in
			stdoutLines.append(data)
		}
		try procInterface.run()
		let exitCode = procInterface.waitForExitCode()
		return CommandResult(exitCode:exitCode, stdout:stdoutLines, stderr:stderrLines)
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
