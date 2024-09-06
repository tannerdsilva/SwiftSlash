import __cswiftslash

extension Int32 {
	/// close the file handle represented by self.
	public func closeFileHandle() {
		close(self)
	}

	/// reads data from self (represented as a system file handle) into the buffer provided.
	public func readFH(into dataBuffer:UnsafeMutablePointer<UInt8>, size readSize:size_t) throws -> size_t {
		repeat {
			// read the data from the file handle.
			let amountRead = read(self, dataBuffer, readSize)
			guard amountRead > -1 else {
				// need to actually think about better ways to handle these at some point.
				switch _cswiftslash_get_errno() {
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

	/// writes the data provided into self (represented as a system file handle).
	/// - parameter dataToWrite: the data to write into the file handle.
	/// - returns: the number of bytes written.
	/// - throws: FileHandleError.error_wouldblock, FileHandleError.error_bad_fh, FileHandleError.error_invalid, FileHandleError.error_io, FileHandleError.error_nospace, FileHandleError.error_unknown.
	/// - note: error conditions for EAGAIN and EINTR are handled internally.
	public func writeFH(_ dataToWrite:borrowing [UInt8]) throws -> size_t {
		return try dataToWrite.withUnsafeBytes { (dataBuffer:UnsafeRawBufferPointer) in
			try writeFH(from:dataBuffer.baseAddress!.assumingMemoryBound(to:UInt8.self), size: dataBuffer.count)
		}
	}

	/// writes the data provided into self (represented as a system file handle).
	/// - parameter dataToWrite: the data to write into the file handle.
	/// - returns: the number of bytes written.
	/// - throws: FileHandleError.error_wouldblock, FileHandleError.error_bad_fh, FileHandleError.error_invalid, FileHandleError.error_io, FileHandleError.error_nospace, FileHandleError.error_unknown.
	/// - note: error conditions for EAGAIN and EINTR are handled internally.
	public func writeFH(_ dataToWrite:UnsafeBufferPointer<UInt8>) throws -> size_t {
		return try writeFH(from:dataToWrite.baseAddress!, size: dataToWrite.count)
	}

	fileprivate func writeFH(from dataBuffer:UnsafePointer<UInt8>, size writeSize:size_t) throws -> size_t {
		repeat {
			// write the data to the file handle.
			let amountWritten = write(self, dataBuffer, writeSize)
			guard amountWritten > -1 else {
				// need to actually think about better ways to handle these at some point.
				switch _cswiftslash_get_errno() {
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
			#if DEBUG
			assert(amountWritten <= writeSize, "amount written is greater than the size of the buffer.")
			#endif
			return amountWritten
		} while true
	}
}