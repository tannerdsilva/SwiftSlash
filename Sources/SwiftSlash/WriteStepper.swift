/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_posix_helpers
import SwiftSlashFuture
import SwiftSlashFHHelpers

/// helps to manage the state of a write operation. a write buffer may take an unknown amount of data when written to, while the amount of data we are holding are received as they are. this struct helps the two substates to work together.
internal struct WriteStepper:~Copyable {

	/// actions that a holder of a WriteStepper can take after a write operation.
	internal enum Action {

		/// the buffer that this instance is representing is fully flushed and can be retired.
		case retireMe

		/// the buffer that this instance is representing still has data that needs to be written.
		case holdMe
	}

	/// the data that is being written to a given file handle.
	private var data:[UInt8]
	
	/// the offset of the data that has been written to the file handle.
	private var offset:size_t = 0

	/// an optional future that will be set as finished when the write operation is complete.
	internal let completeFuture:Future<Void, DataChannel.ChildRead.ParentWrite.Error>?

	/// creates a new instance of WriteStepper.
	internal init(_ dataIn:consuming [UInt8], writeFuture:consuming Future<Void, DataChannel.ChildRead.ParentWrite.Error>?) {
		data = dataIn
		completeFuture = writeFuture
	}

	/// writes more data into the specified file handle.
	internal mutating func write(to writerFH:Int32) throws(FileHandleError) -> Action {
		func exposeBytes(_ dat:UnsafeMutablePointer<UInt8>, count:size_t) throws(FileHandleError) -> size_t {
			return try writerFH.writeFH(UnsafeBufferPointer<UInt8>(start:dat + offset, count:count - offset))
		}
		offset += try exposeBytes(&data, count:data.count)
		if offset == data.count {
			try? completeFuture?.setSuccess(())
			return .retireMe
		} else {
			return .holdMe
		}
	}
}