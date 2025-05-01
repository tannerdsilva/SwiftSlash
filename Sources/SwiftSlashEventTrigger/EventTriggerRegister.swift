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
import SwiftSlashFuture

internal enum Register<DataChannelChildReadError, DataChannelChildWriteError>:Equatable, Hashable where DataChannelChildReadError:Error, DataChannelChildWriteError:Error {

	/// register a parent process reader.
	/// - parameter 1: the file handle to register.
	case reader(fh:Int32, (FIFO<size_t, Never>, Future<Void, DataChannelChildWriteError>)?)


	/// register a parent process writer.
	/// - parameter 1: the file handle to register.
	case writer(fh:Int32, (FIFO<Void, Never>, Future<Void, DataChannelChildReadError>)?)
}

extension Register {
	/// equatable implementation
	internal static func == (lhs:Register, rhs:Register) -> Bool {
		switch (lhs, rhs) {
			case (.reader(fh:let l1, _), .reader(fh:let r1, _)):
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