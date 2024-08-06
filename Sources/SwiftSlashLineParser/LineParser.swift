import __cswiftslash
import SwiftSlashNAsyncStream

/// a line parser.
/// takes raw bytes as input, and passes one or lines to the configured output.
public struct LineParser:~Copyable {
	private static let defaultBufferSize:size_t = 1024

	/// the output mode of the line parser.
	internal enum Output {
		/// the line parser will handle the parsed lines with the given handler.
		case handler(([UInt8]?) -> Void)
		/// the line parser will yield the parsed lines to the given nasyncstream.
		case nasync(NAsyncStream<[UInt8], Never>)
	}

	/// the line pattern to match
	private let match:[UInt8]
	/// the line pattern length
	private var matched:size_t = 0

	/// the intake buffer for the data
	private var intakebuff:UnsafeMutablePointer<UInt8>
	/// the intake buffer length
	private var intakebufflen:size_t

	/// the amount of bytes that have already been processed within the occupied space of the intake buffer
	private var i:size_t = 0
	/// the amount of bytes that are occupied within the intake buffer space
	private var occupied:size_t = 0

	/// the output mode of the line parser
	private let outMode:Output

	/// primary initializer for the line parser. initializes with a separator and the output handler for the parsed lines.
	private init(separator:consuming [UInt8], output:consuming Output) {
		match = separator
		intakebuff = UnsafeMutablePointer<UInt8>.allocate(capacity:Self.defaultBufferSize)
		intakebufflen = Self.defaultBufferSize
		outMode = output
	}
	
	/// initializes the line parser with a separator and a nasyncstream to yield the parsed lines to.
	public init(separator configuration:consuming [UInt8], nasync output:consuming NAsyncStream<[UInt8], Never>) {
		self.init(separator:configuration, output:.nasync(output))
	}

	/// initializes the line parser with a separator and a handler to handle the parsed lines.
	public init(separator configuration:consuming [UInt8], handler output:consuming @escaping ([UInt8]?) -> Void) {
		self.init(separator:configuration, output:.handler(output))
	}

	/// resizes the intake buffer to double its current size.
	private mutating func resizeUp() {
		intakebufflen = intakebufflen * 2
		intakebuff = UnsafeMutablePointer<UInt8>.allocate(capacity:intakebufflen)
	}

	/// prepares the line parser such that it can accomodate up to the given amount of bytes.
	private mutating func intakePrepare(_ bytes:size_t) -> UnsafeMutablePointer<UInt8> {
		while occupied + bytes > intakebufflen {
			resizeUp()
		}
		return intakebuff + occupied
	}

	/// processes the intake buffer.
	private mutating func process() {
		var start = 0
		if match.isEmpty == false {
			while i < occupied {
				if match[matched] == intakebuff[i] {
					matched += 1
					if matched == match.count {
						let line = Array<UInt8>(UnsafeBufferPointer(start: intakebuff + start, count: i - start - matched + 1))
						switch outMode {
						case .handler(let handler):
							handler(line)
						case .nasync(let nas):
							nas.yield(line)
						}
						start = i + 1
						matched = 0
					}
				} else {
					matched = 0
				}
				i += 1
			}
			if start > 0 {
				occupied -= start
				memmove(intakebuff, intakebuff + start, occupied)
			}
			i = 0
		}
	}

	/// intakes the given amount of bytes, and processes them with the given handler.
	///	- parameter bytes: the amount of bytes to intake.
	///	- parameter handler: the handler to process the bytes.
	/// - throws: any error that the handler may throw.
	public mutating func intake(bytes:size_t, _ handler:(UnsafeMutablePointer<UInt8>) throws -> size_t) rethrows {
		let wptr = intakePrepare(bytes)
		let consumed = try handler(wptr)
		occupied += consumed
		process()
	}

	/// handles the given data.
	///	- parameter data: the data to handle.
	public mutating func handle(_ data:consuming [UInt8]) {
		return data.withUnsafeBufferPointer({ datBuff in
			return intake(bytes:datBuff.count, { wptr in
				memcpy(wptr, datBuff.baseAddress!, datBuff.count)
				return datBuff.count
			})
		})
	}

	public consuming func finish() {
		if occupied > 0 {
			let line = Array<UInt8>(UnsafeBufferPointer(start: intakebuff, count: occupied))
			switch outMode {
			case .handler(let handler):
				handler(line)
			case .nasync(let nas):
				nas.yield(line)
			}
		}
	}

	public consuming func finishDataloss() {
		if occupied > 0 {
			let line = Array<UInt8>(UnsafeBufferPointer(start: intakebuff, count: occupied))
			switch outMode {
			case .handler(let handler):
				handler(line)
			case .nasync(let nas):
				nas.yield(line)
			}
		}
	}

	deinit {
		intakebuff.deallocate()
	}
}