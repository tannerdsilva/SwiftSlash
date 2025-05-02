/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

/// represents a path on the hosts filesystem.
public struct Path:Sendable {

	/// the individual components of the path. these are assumed to be separated by their platform specific path separator.
	private var components:[String]

	/// initialize a Path from the contents of a string.
	/// - parameters:
	/// 	- pathString: the string-like object to parse into a path. this string should be a valid path on the host system.
	public init<S>(_ pathString:consuming S) where S:StringProtocol, S.SubSequence == Substring {
		components = pathString.split(separator: "/", omittingEmptySubsequences:true).map(String.init)
	}

	/// initialize a Path by defining the components of the path explicitly in an array.
	/// - parameters:
	/// 	- pathComponents: the components of the path. these are assumed to be separated by their platform specific path separator.
	public init(pathComponents:consuming [String]) {
		components = pathComponents
	}
	
	/// appends a component to the path.
	/// - parameters:
	/// 	- component: the component to append to the path.
	public mutating func appendPathComponent(_ component:consuming String) {
		components.append(component)
	}

	/// returns a new path with the component appended to the path.
	/// - parameters:
	/// 	- component: the component to append to the path.
	/// - returns: a new path with the component appended to the path.
	/// - note: this does not modify the original path.
	public consuming func appendingPathComponent(_ component:consuming String) -> Path {
		var p = self
		p.appendPathComponent(component)
		return p
	}

	/// remove last component from the path.
	public mutating func removeLastComponent() {
		components.removeLast()
	}

	/// returns a new path with the last component removed.
	public consuming func removingLastComponent() -> Path {
		var p = self
		p.removeLastComponent()
		return p
	}

	/// returns the path as a string.
	public consuming func path() -> String {
		return "/" + components.joined(separator: "/")
	}
}

extension Path:CustomStringConvertible {
	/// returns the path as a string.
	public var description:String {
		return path()
	}
}

extension Path:CustomDebugStringConvertible {
	public var debugDescription:String {
		return "Path(\"\(path())\")"
	}
}

extension Path:ExpressibleByStringLiteral {
	/// initialize a path by a string literal value.
	public init(stringLiteral value:consuming String) {
		self.init(value)
	}
}

extension String {
	/// initialize a string from a system host path.
	public init(_ p:consuming Path) {
		self = p.path()
	}
}

extension Path:Hashable, Equatable {
	/// hashable protocol implementation
	public borrowing func hash(into hasher:inout Hasher) {
		hasher.combine(components)
	}
	/// equatable protocol implementation
	public static func == (lhs:consuming Path, rhs:consuming Path) -> Bool {
		return lhs.components == rhs.components
	}
}