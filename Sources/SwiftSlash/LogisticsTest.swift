/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_posix_helpers

/// check if a path is a file and is accessible for execution.
internal func precheckExecute(_ p:UnsafePointer<UInt8>) -> Bool {
	var s = stat()
	#if os(macOS)
	guard stat(p, &s) == 0, UInt16(s.st_mode) & S_IFMT == S_IFREG else {
		return false
	}
	#elseif os(Linux)
	guard stat(p, &s) == 0, Int32(s.st_mode) & S_IFMT == S_IFREG else {
		return false
	}
	#endif
	guard access(p, R_OK | X_OK) == 0 else {
		return false
	}
	return true
}

/// check if a path is a directory and is accessible for execution.
internal func precheckDirectory(_ p:UnsafePointer<UInt8>) -> Bool {
	var s = stat()
	#if os(macOS)
	guard stat(p, &s) == 0, UInt16(s.st_mode) & S_IFMT == S_IFDIR else {
		return false
	}
	#elseif os(Linux)
	guard stat(p, &s) == 0, Int32(s.st_mode) & S_IFMT == S_IFDIR else {
		return false
	}
	#endif
	guard access(p, R_OK | X_OK) == 0 else {
		return false
	}
	return true
}