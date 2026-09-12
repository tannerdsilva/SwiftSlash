/*
LICENSE MIT
copyright (c) tanner silva 2026. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_posix_helpers

extension Int32 {
	/// close the file handle represented by self.
	public func closeFileHandle() throws(FileHandleError) {
		infiniteLoop: repeat {
			let closeResult = close(self)
			guard closeResult == 0 else {
				let errNo = __cswiftslash_get_errno()
				switch errNo {
					case EAGAIN:
						continue infiniteLoop
					case EWOULDBLOCK:
						throw FileHandleError.error_wouldblock;
					case EBADF:
						throw FileHandleError.error_bad_fh;
					case EINTR:
						continue infiniteLoop
					case EINVAL:
						throw FileHandleError.error_invalid;
					case EIO:
						throw FileHandleError.error_io;
					case ENOSPC:
						throw FileHandleError.error_nospace;
					case EDQUOT:
						throw FileHandleError.error_quota;
					default:
						throw FileHandleError.error_unknown(errNo)
				}
			}
			return
		} while true
	}

	/// reads data from self (represented as a system file handle) into the buffer provided.
	/// - parameter dataBuffer: the buffer to read the data into.
	/// - parameter readSize: the size of data to read.
	/// - returns: the number of bytes read.
	public func readFH(into dataBuffer:UnsafeMutablePointer<UInt8>, size readSize:Int) throws(FileHandleError) -> Int {
		infiniteLoop: repeat {
			// read the data from the file handle.
			let amountRead = read(self, dataBuffer, readSize)
			guard amountRead > -1 else {
				let errNo = __cswiftslash_get_errno()
				switch errNo {
					case EAGAIN:
						continue infiniteLoop
					case EWOULDBLOCK:
						throw FileHandleError.error_wouldblock;
					case EBADF:
						throw FileHandleError.error_bad_fh;
					case EINTR:
						continue infiniteLoop
					case EINVAL:
						throw FileHandleError.error_invalid;
					case EIO:
						throw FileHandleError.error_io;
					default:
						throw FileHandleError.error_unknown(errNo)
				}
			}
			return amountRead
		} while true
	}

	/// writes the data provided into self (represented as a system file handle).
	/// - parameter dataToWrite: the data to write into the file handle.
	/// - returns: the number of bytes written.
	/// - throws: FileHandleError.error_wouldblock, FileHandleError.error_bad_fh, FileHandleError.error_invalid, FileHandleError.error_io, FileHandleError.error_nospace, FileHandleError.error_pipe, FileHandleError.error_unknown.
	/// - note: an interruption (EINTR) is handled internally and the write is retried. a non-blocking file handle whose pipe (or socket) is full surfaces as FileHandleError.error_wouldblock and blocks no thread.
	public func writeFH(_ dataToWrite:UnsafeBufferPointer<UInt8>) throws(FileHandleError) -> Int {
		return try writeFH(from:dataToWrite.baseAddress!, size:dataToWrite.count)
	}

	public func writeFH(singleByte:consuming UInt8) throws(FileHandleError) -> Int {
		return try writeFH(from:&singleByte, size:1)
	}

	fileprivate func writeFH(from dataBuffer:UnsafePointer<UInt8>, size writeSize:Int) throws(FileHandleError) -> Int {
		infiniteLoop: repeat {
			// write the data to the file handle.
			let amountWritten = write(self, dataBuffer, writeSize)
			guard amountWritten >= 0 else {
				let errNo = __cswiftslash_get_errno()
				switch errNo {
					case EWOULDBLOCK:
						// a full pipe. on both supported platforms EAGAIN and
						// EWOULDBLOCK share a single value (11 on linux, 35 on
						// darwin), so this case covers the non-blocking "would
						// block" condition of both names. the caller is expected
						// to park on a readiness signal and retry.
						throw FileHandleError.error_wouldblock;
					case EBADF:
						throw FileHandleError.error_bad_fh;
					case EINTR:
						continue infiniteLoop
					case EINVAL:
						throw FileHandleError.error_invalid;
					case EIO:
						throw FileHandleError.error_io;
					case ENOSPC:
						throw FileHandleError.error_nospace;
					case EPIPE:
						// the pipe has no readers (its child exited or closed its
						// end). SIGPIPE is suppressed process-wide (see
						// __cswiftslash_ignore_sigpipe), so this surfaces as a
						// recoverable error instead of terminating the process.
						throw FileHandleError.error_pipe;
					default:
						throw FileHandleError.error_unknown(errNo);
				}
			}
			return amountWritten
		} while true
	}
}
