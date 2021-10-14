import Foundation

internal struct CurrentProcessState {
	internal static func getCurrentEnvironmentVariables() -> [String:String] {
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
	
	internal static func getCurrentWorkingDirectory() -> URL {
		let rawPointer = getcwd(nil, 0)
		let currentWorkingDirectoryBuffer = UnsafeMutableRawPointer(rawPointer!)
		defer {
			free(currentWorkingDirectoryBuffer)
		}
		let length = strlen(rawPointer!)
		let currentWDData = Data(bytes:currentWorkingDirectoryBuffer, count:length)
		let currentPath = String(data:currentWDData, encoding:.utf8)!
		return URL(fileURLWithPath:currentPath)
	}
}