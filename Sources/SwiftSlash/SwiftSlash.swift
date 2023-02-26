// urls are super nice to work with (in terms of adding and removing path components) so these are used in preference to Strings in the public API.
import struct Foundation.URL

/// Possible failure types for a given system resource (file path).
public struct PermissionFailure:OptionSet {

	/// The resource could not be read.
	public static let readingDenied:UInt8 = 1 << 0

	/// The resource could not be executed.
	public static let executeDenied:UInt8 = 1 << 1
	
	/// The raw value of the option set
	public let rawValue:UInt8
	public init(rawValue:UInt8) {
		self.rawValue = rawValue
	}
}

/// Errors that SwiftSlash may throw through the course of its usage.
public enum Error:Swift.Error {

	/// Errors pertaining to the PATH environment variable and searching for non-absolute paths.
	public enum PathSearch:Swift.Error {
		/// Thrown when the PATH variable is not found in the current environment.
		case pathNotFoundInEnvironment

		/// Thrown when the specified program is not found in the PATH's of the current environment.
		/// - Attribute 1: The PATH's found in the current environment that were used for the search.
		/// - Attribute 2: The program name that was not found in the paths.
		case programNotFound([URL], String)

		/// Thrown when the specified program name is found in the PATH's of the current environment, but the program does not have adequate permissions to be launched.
		/// - Attribute 1: The URL of the program that was found.
		/// - Attribute 2: The failures permission failures found for the program.
		case programPermissionError(URL)
	}
	
}
