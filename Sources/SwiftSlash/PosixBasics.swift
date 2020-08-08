import Foundation
import Glibc

//this is the queue that acts as the 'workload root' for the sub-queues that make up the SwiftSlash workload
let swiftslashCaptainQueue = DispatchQueue(label:"com.swiftslash.global.captain", attributes:[.concurrent])

//file handles and pipes are created and closed using this queue
let fileHandleQueue = DispatchQueue(label:"com.swiftslash.global.fh_admin", target:swiftslashCaptainQueue)

internal enum FileHandleError:Error {
	case pollingError;
	case readAllocationError;
	
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

fileprivate let _read = Glibc.read(_:_:_:)
fileprivate let _write = Glibc.write(_:_:_:)

internal struct PosixPipe {
	var reading:Int32
	var writing:Int32
	
	var isNullValued:Bool { 
		get {
			if (reading == -1 && writing == -1) {
				return true
			} else {
				return false
			}
		}
	}
	
	init() {
		var readingValue:Int32 = -1
		var writingValue:Int32 = -1
		
		let fds = UnsafeMutablePointer<Int32>.allocate(capacity:2)
		defer {
			fds.deallocate()
		}
		fileHandleQueue.sync {
			switch pipe(fds) {
				case 0:
					readingValue = fds.pointee
					writingValue = fds.successor().pointee
				default:
					break;
			}
		}
		self.reading = readingValue
		self.writing = writingValue
	}
	
	init(reading:Int32, writing:Int32) {
		self.reading = reading
		self.writing = writing
	}
}

internal enum PollResult {
	case readable
	case writable
	case pipeTerm
	case waiting
}

extension Array where Element == pollfd {
	internal func poll(timeoutMicroseconds:Int32) throws -> [Int32:PollResult] {
		let fdsToMonitor = UnsafeMutablePointer<pollfd>.allocate(capacity:self.count)
		defer {
			fdsToMonitor.deallocate()
		}
		for (i, curInstruction) in enumerated() {
			fdsToMonitor[i] = curInstruction
		}
		guard Glibc.poll(fdsToMonitor, nfds_t(self.count), timeoutMicroseconds) >= 0 else {
			print("Poll failed to execute")
			throw FileHandleError.pollingError
		}
		var i = 0
		var pollResultBuild = [Int32:PollResult]()
		while i < self.count {
			let returnEvents = fdsToMonitor[i].revents
			if returnEvents & Int16(POLLIN) != 0 {
				pollResultBuild[fdsToMonitor[i].fd] = PollResult.readable
			} else if returnEvents & Int16(POLLOUT) != 0 {
				pollResultBuild[fdsToMonitor[i].fd] = PollResult.writable
			} else if returnEvents & Int16(POLLERR) != 0 || returnEvents & Int16(POLLHUP) != 0 {
				pollResultBuild[fdsToMonitor[i].fd] = PollResult.pipeTerm
			} else {
				pollResultBuild[fdsToMonitor[i].fd] = PollResult.waiting
			}
			i = i + 1
		}
		return pollResultBuild
	}
}

extension Int32 {
	internal func pollReading(timeoutMilliseconds:Int32 = 0) throws -> PollResult {
		var pfd = self.pollfd_read()
		let pollResult = Glibc.poll(&pfd, nfds_t(1), timeoutMilliseconds)
		guard pollResult >= 0 else { 
			throw FileHandleError.pollingError
		}
		let pollinFlag = Int16(POLLIN)
		let pollClosedFlag = Int16(POLLHUP)
		if (pfd.revents & pollinFlag == pollinFlag) {
			return PollResult.readable
		} else if (pfd.revents & pollClosedFlag == pollClosedFlag) {
			return PollResult.pipeTerm
		} else {
			return PollResult.waiting
		}
	}
	
	internal func pollWriting(timeoutMilliseconds:Int32 = 0) throws -> PollResult {
		var pfd = self.pollfd_write()
		let pollResult = Glibc.poll(&pfd, nfds_t(1), timeoutMilliseconds)
		guard pollResult >= 0 else { 
			throw FileHandleError.pollingError
		}
		let polloutFlag = Int16(POLLOUT)
		let pollClosedFlag = Int16(POLLERR)
		if (pfd.revents & polloutFlag == polloutFlag) {
			return PollResult.writable
		} else if (pfd.revents & pollClosedFlag == pollClosedFlag) {
			return PollResult.pipeTerm
		} else {
			return PollResult.waiting
		}
	}
	
	internal func readFileHandle() throws -> Data {
		guard let readAllocation = malloc(Int(PIPE_BUF) + 1) else {
			throw FileHandleError.error_unknown
		}
		defer {
			free(readAllocation)
		}
		let amountRead = read(self, readAllocation, Int(PIPE_BUF))
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
		if let utf8Data = inputString.data(using:.utf8) {
			print("data converted")
			print("\(utf8Data)")
			return try String(data:self.writeFileHandle(utf8Data), encoding:.utf8) ?? ""
		}
		return ""
	}
	
	internal func writeFileHandle(_ inputData:Data) throws -> Data {
		if (inputData.count <= 0) {
			return Data()
		}
		let prefixedData = inputData.prefix(Int(PIPE_BUF))
		let amountWritten = prefixedData.withUnsafeBytes { (startBuff) -> Int in 
			print("attempting to write \(prefixedData.count) bytes")
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
	
	fileprivate func pollfd_read() -> pollfd {
		var returnStruct = pollfd()
		returnStruct.fd = self
		returnStruct.events = Int16(POLLIN)
		return returnStruct
	}
	
	fileprivate func pollfd_write() -> pollfd {
		var returnStruct = pollfd()
		returnStruct.fd = self
		returnStruct.events = Int16(POLLOUT)
		return returnStruct
	}
}

var myPipe = PosixPipe()
let writeLeftovers = try myPipe.writing.writeFileHandle("foo")
print("Successfully wrote the thing. '\(writeLeftovers)'")
let capturedData = try myPipe.reading.readFileHandle()
print("\(try myPipe.reading.pollReading(500))")
let capAsString = String(data:capturedData, encoding:.utf8)

print("\(capAsString)")