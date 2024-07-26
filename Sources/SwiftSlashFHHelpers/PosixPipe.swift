import __cswiftslash

/// represents the low level system construct that enables inter-process communication.
public struct PosixPipe:Hashable, Equatable {
	
	// fh that is used for reading from the pipe.
	public let reading:Int32
	// fh that is used for writing to the pipe.
	public let writing:Int32
	
	/// create a new pipe with the specified options.
	public init(nonblockingReads:Bool = false, nonblockingWrites:Bool = false) throws {
		var fds:(Int32, Int32) = (-1, -1)
		(self.reading, self.writing) = try withUnsafeMutablePointer(to:&fds) { fdsPtr in
			switch pipe(UnsafeMutableRawPointer(fdsPtr).assumingMemoryBound(to:Int32.self)) {
				case 0:
					return (fdsPtr.pointee.0, fdsPtr.pointee.1)
				default:
					throw SystemErrno(errno)
			}
		}
		if (nonblockingReads == true) {
			guard fcntl(reading, F_SETFD, O_NONBLOCK) == 0 else {
				throw FileHandleError.fcntlError
			}
		}
		if (nonblockingWrites == true) {
			guard fcntl(writing, F_SETFD, O_NONBLOCK) == 0 else {
				throw FileHandleError.fcntlError
			}
		}
	}
	
	/// create a new pipe with the specified options.
	private init(reading rArg:Int32, writing wArg:Int32) {
		reading = rArg
		writing = wArg
	}
	
	/// creates a "pseudo pipe" that reads and writes directly to /dev/null.
	public static func createNull() throws -> PosixPipe {
		let read = open("/dev/null", O_RDWR)
		let write = open("/dev/null", O_WRONLY)
		_ = fcntl(read, F_SETFL, O_NONBLOCK)
		_ = fcntl(write, F_SETFL, O_NONBLOCK)
		guard read != -1 && write != -1 else {
			throw FileHandleError.pipeOpenError
		}
		return PosixPipe(reading:read, writing:write)
	}
	
	// hashable conformance
	public func hash(into hasher:inout Hasher) {
		hasher.combine(reading)
		hasher.combine(writing)
	}
	
	// equatable conformance
	public static func == (lhs:PosixPipe, rhs:PosixPipe) -> Bool {
		return (lhs.reading == rhs.reading) && (rhs.writing == rhs.writing)
	}
}
