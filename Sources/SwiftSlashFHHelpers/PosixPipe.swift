import __cswiftslash

/// represents the low level system construct that enables inter-process communication.
public struct PosixPipe:Hashable, Equatable {
	
	// fh that is used for reading from the pipe.
	public let reading:Int32
	// fh that is used for writing to the pipe.
	public let writing:Int32

	/// returns a pipe that is used for reading from the child process.
	/// - writing end is blocking.
	/// - reading end is nonblocking.
	public static func forChildWriting() throws -> PosixPipe {
		return try PosixPipe(nonblockingReads:true, nonblockingWrites:false)
	}

	/// returns a pipe that is used for writing to the child process.
	/// - writing end is nonblocking.
	/// - reading end is blocking.
	public static func forChildReading() throws -> PosixPipe {
		return try PosixPipe(nonblockingReads:false, nonblockingWrites:true)
	}

	
	/// create a new pipe with the specified options.
	public init(nonblockingReads:Bool = false, nonblockingWrites:Bool = false) throws {
		var fds:(Int32, Int32) = (-1, -1)
		(self.reading, self.writing) = try withUnsafeMutablePointer(to:&fds) { fdsPtr in
			switch pipe(UnsafeMutableRawPointer(fdsPtr).assumingMemoryBound(to:Int32.self)) {
				case 0:
					return (fdsPtr.pointee.0, fdsPtr.pointee.1)
				default:
					throw SystemErrno(_cswiftslash_get_errno())
			}
		}
		if (nonblockingReads == true) {
			guard _cswiftslash_fcntl_setfl(reading, O_NONBLOCK) == 0 else {
				throw FileHandleError.fcntlError
			}
		}
		if (nonblockingWrites == true) {
			guard _cswiftslash_fcntl_setfl(writing, O_NONBLOCK) == 0 else {
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
		let read = _cswiftslash_open_nomode("/dev/null", O_RDONLY)
		let write = _cswiftslash_open_nomode("/dev/null", O_WRONLY)
		_ = _cswiftslash_fcntl_setfl(read, O_NONBLOCK)
		_ = _cswiftslash_fcntl_setfl(write, O_NONBLOCK)
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
