import func Foundation.unsetenv
import var Foundation.environ
import struct Foundation.URL
import struct Foundation.Data
import func Foundation.access
import var Foundation.F_OK
import func Foundation.getcwd
import func Foundation.strlen
import func Foundation.free
import func Foundation.memcmp
import func Foundation.malloc

/// A struct that contains static functions for querying the current process state.
public struct CurrentProcessState {

	/// Clears the environment variables for the currently running process.
    internal static func clearEnvironmentVariables() -> Int32 {
        let currentEnvs = CurrentProcessState.getCurrentEnvironmentVariables()
        for curEnv in currentEnvs {
            let unsetResult = unsetenv(curEnv.key)
            if unsetResult != 0 {
                return unsetResult
            }
        }
        return 0
    }

	/// Returns the current environment variables for the currently running process.
	/// - Returns: A dictionary of all environment variables.
	public static func getCurrentEnvironmentVariables() -> [String:String] {
		var i = 0
		var buildEnv = [String:String]()
		while let curPtr = environ[i] {
			let curEnvString = String(cString:curPtr)
			let splitEnv = curEnvString.split(separator:"=").compactMap { String($0) }
            switch splitEnv.count {
                case 1:
                    buildEnv[splitEnv[0]] = ""
                case 2:
                    buildEnv[splitEnv[0]] = splitEnv[1]
                default:
                    break;
            }
			i = i + 1
		}
		return buildEnv
	}
	
	/// Returns the current working directory for the currently running process.
	/// - Returns: A URL to the current working directory.
	public static func getCurrentWorkingDirectory() -> URL {
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

	/// Searches the system paths for an executable with a given name. 
	/// - Throws: This function throws `SwifeSlash.Error.PathSearch` errors exclusively.
	/// - Returns: The path to the executable if it is found.
	internal static func searchCurrentPathsForExecutable(_ executable:String) throws -> String {
		var i = 0
		while let curPtr = environ[i] {
			// search the environment variables for PATH key
			if memcmp(curPtr, "PATH=", 5) == 0 {
				// key found. capture the value of the PATH variable as a String
				let curEnvString = String(cString:curPtr.advanced(by:5))
				// find all the paths in the value
				let envPaths = curEnvString.split(separator:":").compactMap { URL(fileURLWithPath:String($0)) }
				for curPath in envPaths {
					// check if the executable exists in the current path
					let curExecutablePath = curPath.appendingPathComponent(executable, isDirectory:false)
					let existCheck = access(curExecutablePath.path, F_OK)
					guard existCheck == 0 else {
						continue;
					}
					// the file exists, return the path
					return curExecutablePath.path
				}
				// throw an error because the executable was not found in any of the paths
				throw Error.PathSearch.programNotFound(envPaths, executable)
			}
			i = i + 1
		}
		// throw an error because the PATH variable was not found in the environment
		throw Error.PathSearch.pathNotFoundInEnvironment
	}
}
