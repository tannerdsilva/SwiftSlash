import __cswiftslash

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

public struct CurrentProcess {
	private init() {} // this is just a namespace - no instances allowed.
	public enum PathSearchError:Swift.Error {
		case pathNotFoundInEnvironment
		case executableNotFound([String], Path)
	}
}

extension CurrentProcess {
	public static func clearEnvironmentVariables() -> Int32 {
		let currentEnvs = environmentVariables()
		for (key, _) in currentEnvs {
			guard unsetenv(key) == 0 else {
				return errno
			}
		}
		return 0
	}

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

	/// returns the current working directory path of the process the function is called from.
	public static func workingDirectory() -> String {
		let rawPointer = getcwd(nil, 0)
		defer {
			free(rawPointer)
		}
		guard rawPointer != nil else {
			fatalError("swiftslash - attempted to get the current working directory of current process (pid \(getpid()))...got a NULL string instead. \(#file):\(#line)")
		}
		return String(cString:rawPointer!)
	}

	public static func searchPaths(executableName:String) throws -> String {
		var i = 0
		mainLoop: while let curPtr = environ[i] {
			defer {
				i = i + 1
			}

			// we are only handling an entry that starts with "PATH="
			guard memcmp(curPtr, "PATH=", 5) == 0 else {
				continue mainLoop;
			}

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
				return curExecutablePath.path()
			}
			i = i + 1

		}
		// throw an error because the PATH variable was not found in the environment
		throw PathSearchError.pathNotFoundInEnvironment
	}
}