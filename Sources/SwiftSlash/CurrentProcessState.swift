/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_posix_helpers

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

/// A namespace for static functions that provide information about the current process.
public struct CurrentProcess {}
extension CurrentProcess {
	/// Clears all environment variables for the current process.
	/// Iterates over each key in the current environment and calls `unsetenv(_:)`.
	/// - Returns: Zero on success; if any call to `unsetenv` fails, returns the corresponding `errno` value.
	internal static func clearEnvironmentVariables() -> Int32 {
		let currentEnvs = environmentVariables()
		for (key, _) in currentEnvs {
			guard unsetenv(key) == 0 else {
				return errno
			}
		}
		return 0
	}

	/// Retrieves the environment variables of the current process.
	/// Parses the global `environ` array into a `[String:String]` dictionary.
	/// Keys without an explicit “=`value`” part will be mapped to an empty string.
	/// - Returns: A dictionary mapping each environment variable name to its value.
	public static func environmentVariables() -> [String:String] {
		var i = 0
		var envs:[String:String] = [:]
		while let curPtr = environ[i] {
			let curEnvString = String(cString:curPtr)
			let curEnv = curEnvString.split(separator:"=", maxSplits:1)
			switch curEnv.count {
				case 1:
					envs[String(curEnv[0])] = ""
				case 2:
					envs[String(curEnv[0])] = String(curEnv[1])
				default:
					fatalError("swiftslash - attempted to parse an environment variable from the current process (pid \(getpid()))...got an unexpected number of components. \(#file):\(#line)")
			}
			i = i + 1
		}
		return envs
	}

	/// Returns the current working directory of the calling process.
	/// - Returns: A `Path` representing the process’s current working directory.
	public static func workingDirectory() -> Path {
		let rawPointer = getcwd(nil, 0)
		defer {
			free(rawPointer)
		}
		return Path(String(cString:rawPointer!))
	}

	/// Searches all directories in `path` for the given executable name.
	/// - Parameter executablename: the name of the executable to locate.
	/// - Throws:
	/// 	- `PathSearchError.pathNotFoundInEnvironment` if the `PATH` variable is missing.
	/// 	- `PathSearchError.executableNotFound(foundPaths: [String], executable: Path)`
	/// 		if `PATH` is present but the executable cannot be located in any listed directory.
	/// - Returns: A `Path` pointing to the first matching executable file.
	public static func searchPaths(executableName:String) throws(PathSearchError) -> Path {
		var i = 0
		var foundPath:Bool = false
		mainLoop: while let curPtr = environ[i] {
			defer {
				i = i + 1
			}
			// we are only handling an entry that starts with "PATH="
			guard memcmp(curPtr, "PATH=", 5) == 0 else {
				continue mainLoop;
			}
			foundPath = true
			// key found. capture the value of the PATH variable as a String
			let curEnvString = String(cString:curPtr.advanced(by:5))
			// find all the paths in the value
			let envPaths = curEnvString.split(separator:":")
			pathsLoop: for curPath in envPaths {

				// check if the executable exists in the current path
				let curExecutablePath = Path(curPath).appendingPathComponent(executableName)
				let existCheck = access(curExecutablePath.path(), F_OK)
				guard existCheck == 0 else {
					continue pathsLoop;
				}

				// the file exists, return the path
				return curExecutablePath
			}
		}
		switch foundPath {
			case true:
				// if we found the PATH variable but did not find the executable, throw an error
				throw PathSearchError.executableNotFound(Array(environmentVariables().keys), Path(executableName))
			case false:
				throw PathSearchError.pathNotFoundInEnvironment
		}
	}
}