/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_eventtrigger
import SwiftSlashFIFO

internal enum Register:Equatable, Hashable {

	/// register a reader.
	/// - parameter 1: the file handle to register.
	/// - parameter 2: the fifo to signal when there is data to read from the file handle.
	case reader(Int32, FIFO<size_t, Never>?)


	/// register a writer.
	/// - parameter 1: the file handle to register.
	/// - parameter 2: the fifo to signal when there is space to write more data to the file handle.
	case writer(Int32, FIFO<Void, Never>?)
}

extension Register {
	/// equatable implementation
	internal static func == (lhs:Register, rhs:Register) -> Bool {
		switch (lhs, rhs) {
			case (.reader(let l1, _), .reader(let r1, _)):
				return l1 == r1
			case (.writer(let l1, _), .writer(let r1, _)):
				return l1 == r1
			default:
				return false
		}
	}

	/// hashable implementation
	internal func hash(into hasher:inout Hasher) {
		switch self {
			case .reader(let i, _):
				hasher.combine(true)
				hasher.combine(i)
			case .writer(let i, _):
				hasher.combine(false)
				hasher.combine(i)
		}
	}
}