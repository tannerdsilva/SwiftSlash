import __cswiftslash

extension Int32 {
	/// reads data from self (represented as a system file handle) into the buffer provided.
	internal func readFH(into dataBuffer:UnsafeMutableBufferPointer<UInt8>, size readSize:size_t) throws -> size_t {
		repeat {
			// read the data from the file handle.
			let amountRead = read(self, dataBuffer.baseAddress, readSize)
			guard amountRead > -1 else {
				// need to actually think about better ways to handle these at some point.
				switch errno {
					case EAGAIN:
						continue
					case EWOULDBLOCK:
						throw FileHandleError.error_wouldblock;
					case EBADF:
						throw FileHandleError.error_bad_fh;
					case EINTR:
						continue
					case EINVAL:
						throw FileHandleError.error_invalid;
					case EIO:
						throw FileHandleError.error_io;
					default:
						throw FileHandleError.error_unknown;
				}
			}
			return amountRead
		} while true
	}

	/// writes data from the buffer provided into self (represented as a system file handle).
	internal func writeFH(from dataBuffer:UnsafePointer<UInt8>, size writeSize:size_t) throws -> size_t {
		repeat {
			// write the data to the file handle.
			let amountWritten = write(self, dataBuffer, writeSize)
			guard amountWritten > -1 else {
				// need to actually think about better ways to handle these at some point.
				switch errno {
					case EAGAIN:
						continue
					case EWOULDBLOCK:
						throw FileHandleError.error_wouldblock;
					case EBADF:
						throw FileHandleError.error_bad_fh;
					case EINTR:
						continue
					case EINVAL:
						throw FileHandleError.error_invalid;
					case EIO:
						throw FileHandleError.error_io;
					case ENOSPC:
						throw FileHandleError.error_nospace;
					default:
						throw FileHandleError.error_unknown;
				}
			}
			return amountWritten
		} while true
	}
}