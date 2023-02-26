import Foundation
#if os(Linux)
import Glibc
#endif

internal enum FileHandleError:Swift.Error {
	case pollingError;
	case readAllocationError;
	
	case pipeOpenError;
	
	case fcntlError;
	
	case error_unknown;
	
	case error_again;
	case error_wouldblock;
	case error_bad_fh;
	case error_interrupted;
	case error_invalid;
	case error_io;
	case error_nospace;
	
	case error_pipe;
}

internal struct PosixPipe:Hashable {
	var reading:Int32
	var writing:Int32
	
	var isInvalid:Bool { 
		get {
			if (reading == -1 && writing == -1) {
				return true
			} else {
				return false
			}
		}
	}
	
	init(nonblockingReads:Bool = false, nonblockingWrites:Bool = false) throws {
		var readingValue:Int32 = -1
		var writingValue:Int32 = -1
		
		let fds = UnsafeMutablePointer<Int32>.allocate(capacity:2)
		defer {
			fds.deallocate()
		}
		//assign the new file handles
		switch pipe(fds) {
			case 0:
				readingValue = fds.pointee
				writingValue = fds.successor().pointee
			default:
				print("PIPE ERROR \(errno) \(EMFILE)")
				break;
		}
		if (nonblockingReads == true) {
			guard fcntl(readingValue, F_SETFD, O_NONBLOCK) == 0 else {
				throw FileHandleError.fcntlError
			}
		}
		if (nonblockingWrites == true) {
			guard fcntl(writingValue, F_SETFD, O_NONBLOCK) == 0 else {
				throw FileHandleError.fcntlError
			}
		}
		self.reading = readingValue
		self.writing = writingValue
	}
	
	init(reading:Int32, writing:Int32) {
		self.reading = reading
		self.writing = writing
	}
	
	static func createNullPipe() throws -> PosixPipe {
		let read = open("/dev/null", O_RDWR)
		let write = open("/dev/null", O_WRONLY)
		_ = fcntl(read, F_SETFL, O_NONBLOCK)
		_ = fcntl(write, F_SETFL, O_NONBLOCK)
		guard read != -1 && write != -1 else {
			throw FileHandleError.pipeOpenError
		}
		return PosixPipe(reading:read, writing:write)
	}
	
	
	func hash(into hasher:inout Hasher) {
		hasher.combine(reading)
		hasher.combine(writing)
	}
	
	static func == (lhs:PosixPipe, rhs:PosixPipe) -> Bool {
		return (lhs.reading == rhs.reading) && (rhs.writing == rhs.writing)
	}
}

extension Int32 {
	internal func readFileHandle(size:Int) throws -> Data {
		guard let readAllocation = malloc(size + 1) else {
			throw FileHandleError.error_unknown
		}
		defer {
			free(readAllocation)
		}
		let amountRead = read(self, readAllocation, size)
		guard amountRead > -1 else {
			switch errno {
				case EAGAIN:
					throw FileHandleError.error_again;
				case EWOULDBLOCK:
					throw FileHandleError.error_wouldblock;
				case EBADF:
					throw FileHandleError.error_bad_fh;
				case EINTR:
					throw FileHandleError.error_interrupted;
				case EINVAL:
					throw FileHandleError.error_invalid;
				case EIO:
					throw FileHandleError.error_io;
				default:
					throw FileHandleError.error_unknown;
			}
		}
		guard amountRead != 0 else {
			throw FileHandleError.error_pipe
		}
		let boundBytes = readAllocation.bindMemory(to:UInt8.self, capacity:amountRead)
		return Data(bytes:boundBytes, count:amountRead)
	}
	
	internal func writeFileHandle(_ inputString:String) throws -> String {
		let utf8Data = inputString.data(using:.utf8)
		if (utf8Data != nil) {
			return try String(data:self.writeFileHandle(utf8Data!), encoding:.utf8) ?? ""
		} else {
			throw FileHandleError.error_unknown
		}
	}
	
	internal func writeFileHandle(_ inputData:Data) throws -> Data {
		if (inputData.count <= 0) {
			return Data()
		}
		let prefixedData = inputData.prefix(Int(PIPE_BUF))
		let amountWritten = prefixedData.withUnsafeBytes { (startBuff) -> Int in 
			return write(self, startBuff.baseAddress, prefixedData.count)
		}
		guard amountWritten > -1 else {
			switch errno {
				case EAGAIN:
					throw FileHandleError.error_again;
				case EWOULDBLOCK:
					throw FileHandleError.error_wouldblock;
				case EBADF:
					throw FileHandleError.error_bad_fh;
				case EINTR:
					throw FileHandleError.error_interrupted;
				case EINVAL:
					throw FileHandleError.error_invalid;
				case EIO:
					throw FileHandleError.error_io;
				case ENOSPC:
					throw FileHandleError.error_nospace;
				case EPIPE:
					throw FileHandleError.error_pipe;
				default:
					throw FileHandleError.error_unknown;
			}
		}
		return inputData.suffix(from:amountWritten)
	}
	
	internal func closeFileHandle() {
		close(self);
	}
}
