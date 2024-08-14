import __cswiftslash
import SwiftSlashNAsyncStream

/// the part of the line parser that handles the byte buffer logistics. helps reduce data copying and excessive memory allocation.
fileprivate struct BufferLogistics:~Copyable {
	/// the size of buffer to allocate on initialization.
	private static let defaultBufferSize:size_t = 256
	/// the intake buffer for the data.
	private var intakebuff:UnsafeMutableBufferPointer<UInt8> = UnsafeMutableBufferPointer<UInt8>.allocate(capacity:defaultBufferSize)
	/// the space in the buffer that is occupied.
	private var occupied:size_t = 0

	/// intakes the given amount of bytes.
	///	- parameter bytes: the amount of bytes to intake.
	///	- parameter writeHandler: the handler to write the bytes to the buffer after the space has been prepared.
	/// - throws: any error that the handler may throw. if the handler is thrown, any bytes written to the buffer will be discarded.
	fileprivate mutating func intake(bytes:size_t, _ writeHandler:(UnsafeMutableBufferPointer<UInt8>) throws -> size_t) rethrows {
		// prepare the buffer to accept the specified number of bytes
		let wptr: UnsafeMutableBufferPointer<UInt8> = intakePrepare(addingBytes:bytes)
		let written = try writeHandler(wptr)
		occupied += written
	}

	fileprivate mutating func process(_ accessHandler:(UnsafeMutableBufferPointer<UInt8>) throws -> size_t?) rethrows {
		let stride = try accessHandler(UnsafeMutableBufferPointer<UInt8>(start:intakebuff.baseAddress, count:occupied))
		#if DEBUG
		if stride != nil {
			guard stride! <= occupied else {
				fatalError("this should never happen")
			}
		}
		#endif
		if stride != nil {
			occupied -= stride!
			memmove(intakebuff.baseAddress!, intakebuff.baseAddress! + stride!, occupied)
		}
	}

	/// prepare the buffer to accept the specified number of bytes.
	/// - returns: the region of memory that can accomodate the specified number of bytes.
	/// - parameter newByteAddition: the number of bytes to accomodate.
	private mutating func intakePrepare(addingBytes newByteAddition:size_t) -> UnsafeMutableBufferPointer<UInt8> {
		// if the buffer does not have enough space to accomodate the new bytes, resize so that there is room for the specified number of bytes to occupy the buffer.
		if (occupied + newByteAddition) > intakebuff.count {
			resizeUp(accomodate:occupied + newByteAddition)
		}

		#if DEBUG
		// this should never happen but throwing this in here for good measure
		guard occupied + newByteAddition <= intakebuff.count else {
			fatalError("intake buffer overflow. \(occupied) + \(newByteAddition) > \(intakebuff.count)")
		}
		#endif

		return UnsafeMutableBufferPointer<UInt8>(start:intakebuff.baseAddress! + occupied, count:intakebuff.count - occupied)
	}

	/// resizes the intake buffer to accomodate a specified amount of bytes.
	private mutating func resizeUp(accomodate:size_t) {
		#if DEBUG
		// this should never happen but its here to check things when in debug mode for good measure.
		guard accomodate > 0 else {
			fatalError("cannot resize intake buffer to accomodate zero bytes.")
		}
		#endif

		let targetSize = size_t(ceil(Double(accomodate) / 8) * 8) * 2
		let newBuffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity:targetSize)
		if occupied > 0 {
			memcpy(newBuffer.baseAddress, intakebuff.baseAddress, occupied)
		}
		intakebuff.deallocate()
		intakebuff = newBuffer
	}

	deinit {
		intakebuff.deallocate()
	}
}

/// a line parser.
/// takes raw bytes as input, and passes one or lines to the configured output.
public struct LineParser:~Copyable {

	/// the output mode of the line parser.
	internal enum Output {
		/// the line parser will handle the parsed lines with the given handler.
		case handler(([UInt8]?) -> Void)
		/// the line parser will yield the parsed lines to the given nasyncstream.
		case nasync(NAsyncStream<[UInt8], Never>)
	}

	/// contains the variables relevant to separating individual lines of the byte stream.
	internal struct SeparatorInfo {
		private let match:[UInt8]
		private var matched:size_t = 0
		internal init(exactBytes:consuming [UInt8]) {
			match = exactBytes
		}

		// returns true if the separator is zero length
		internal borrowing func isEmpty() -> Bool {
			return match.count == 0
		}

		/// steps the parser through the matching process.
		/// - parameter bytePtr: the pointer to the byte to match. this inout parameter is modified to point to the next byte in the buffer.
		/// - returns: a pointer to the last byte in the line if the line is completed, nil if the data was stepped without matching the separator.
		internal mutating func stepMatch(_ bytePtr:inout UnsafeMutablePointer<UInt8>) -> UnsafeMutablePointer<UInt8>? {
			
			#if DEBUG
			guard match.count > 0 else {
				fatalError("this should never happen")
			}
			#endif
			
			// determine if the match pattern is fully stepped.
			if bytePtr.pointee == match[matched] {
				matched += 1
				if matched == match.count {
					matched = 0
					bytePtr += 1
					return bytePtr - match.count
				} else {
					bytePtr += 1
					return nil
				}
			} else {
				switch matched {
					case 0:
						break
					default:
						bytePtr -= matched
						matched = 0
				}
				bytePtr += 1
				return nil
			}
		}

		internal borrowing func matchLength() -> size_t {
			return match.count
		}
	}

	/// defines the separator that a given instance is searching for. also helps manage the state of this 'seek' exercise.
	private var separator:SeparatorInfo

	/// primary data buffer for the line parser to process and intake data.
	private var dataLogistics = BufferLogistics()

	/// the intake buffer pointer
	private var existingSeekOffset:size_t = 0

	/// the output mode of the line parser
	private let outMode:Output

	/// primary initializer for the line parser. initializes with a separator and the output handler for the parsed lines.
	private init(separator lineSep:consuming [UInt8], output:consuming Output) {
		separator = SeparatorInfo(exactBytes:lineSep)
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

	/// parses through the storage buffer up to the completion of the line separator.
	private static func processLine(separatorInfo:inout SeparatorInfo, storageBuffer:UnsafeMutableBufferPointer<UInt8>, existingSeekOffset:inout size_t, outputMode:Output) -> size_t {
		var seekPointer = storageBuffer.baseAddress! + existingSeekOffset
		var lineStart = storageBuffer.baseAddress!
		let overflowPointer = storageBuffer.baseAddress! + storageBuffer.count
		stepLoop: while seekPointer < overflowPointer {
			if let newItem = separatorInfo.stepMatch(&seekPointer) {
				let asBuffer = UnsafeBufferPointer(start:lineStart, count:newItem - lineStart)
				defer {
					lineStart = seekPointer
				}
				switch outputMode {
				case .handler(let handler):
					handler(Array(asBuffer))
				case .nasync(let nas):
					nas.yield(Array(asBuffer))
				}
			}
		}
		existingSeekOffset = seekPointer - lineStart
		return (lineStart - storageBuffer.baseAddress!)
	}

	/// intakes the given amount of bytes, and processes them with the given handler.
	///	- parameter bytes: the amount of bytes to intake.
	///	- parameter writeHandler: the handler to write the bytes to the buffer.
	/// - throws: any error that the handler may throw.
	public mutating func intake(bytes:size_t, _ writeHandler:(UnsafeMutableBufferPointer<UInt8>) throws -> size_t) rethrows {
		try dataLogistics.intake(bytes:bytes, writeHandler)
		if separator.isEmpty() == false {
			dataLogistics.process { buff in
				return LineParser.processLine(separatorInfo:&separator, storageBuffer:buff, existingSeekOffset:&existingSeekOffset, outputMode:outMode)
			}
		} else {
			dataLogistics.process { buff in
				let data = Array(UnsafeBufferPointer(start:buff.baseAddress!, count:buff.count))
				switch outMode {
				case .handler(let handler):
					handler(data)
				case .nasync(let nas):
					nas.yield(data)
				}
				return buff.count
			}
		}
	}

	/// handles the given data.
	///	- parameter data: the data to pass into the line parser.
	public mutating func handle(_ data:consuming [UInt8]) {
		return data.withUnsafeBufferPointer({ datBuff in
			return intake(bytes:datBuff.count, { wptr in
				memcpy(wptr.baseAddress, datBuff.baseAddress!, datBuff.count)
				return datBuff.count
			})
		})
	}

	public mutating func finish() {
		dataLogistics.process { buff in
			switch outMode {
			case .handler(let handler):
				if buff.count > 0 {
					let data = Array(UnsafeBufferPointer(start:buff.baseAddress!, count:buff.count))
					handler(data)
				}
				handler(nil)

			case .nasync(let nas):
				if buff.count > 0 {
					let data = Array(UnsafeBufferPointer(start:buff.baseAddress!, count:buff.count))
					nas.yield(data)
				}
				nas.finish()
			}
			return buff.count
		}
	}

	public mutating func finishDataloss() {
		switch outMode {
			case .handler(let handler):
				handler(nil)
			case .nasync(let nas):
				nas.finish()
		}
	}

	deinit {
		switch outMode {
			case .handler(let handler):
				handler(nil)
			case .nasync(let nas):
				nas.finish()
		}
	}
}