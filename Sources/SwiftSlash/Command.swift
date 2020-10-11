import Foundation
import Glibc

public struct Command {
	var executable:String
	var arguments:[String]
	var environment:[String:String] = getCurrentEnvironment()
	
	init?(command:String) {
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
	init?(bash command:String) {
		guard command.count > 0 else {
			return nil
		}
		
		let commandTerminate = "\(command.replacingOccurrences(of:"'", with:"''"))"
		self.executable = "/bin/bash"
		self.arguments = ["-c", commandTerminate]
	}
}

fileprivate func getCurrentEnvironment() -> [String:String] {
	var i = 0
	var buildEnv = [String:String]()
	while let curPtr = environ[i] {
		let curEnvString = String(cString:curPtr)
		let splitEnv = curEnvString.split(separator:"=").compactMap { String($0) }
		buildEnv[splitEnv[0]] = splitEnv[1]
		i = i + 1
	}
	return buildEnv
}
