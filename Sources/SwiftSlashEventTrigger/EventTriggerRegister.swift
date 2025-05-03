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

internal enum Register<DataChannelChildReadError, DataChannelChildWriteError> where DataChannelChildReadError:Error, DataChannelChildWriteError:Error {

	/// register a parent process reader.
	case reader(FIFO<size_t, Never>, Future<Void, DataChannelChildWriteError>)


	/// register a parent process writer.
	case writer(FIFO<Void, Never>, Future<Void, DataChannelChildReadError>)
}