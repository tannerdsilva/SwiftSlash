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

	fileprivate borrowing func access<R>(_ accessHandler:(UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
		return try accessHandler(UnsafeBufferPointer<UInt8>(start:intakebuff.baseAddress, count:occupied))
	}

	fileprivate mutating func rebase(offset:size_t) {
		occupied -= offset
		if occupied > 0 {
			memcpy(intakebuff.baseAddress, intakebuff.baseAddress! + offset, occupied)
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

		// returns true if the current byte matches the current matching index of the pattern
		internal borrowing func doesMatch(_ byte:UInt8) -> Bool {
			#if DEBUG
			guard match.count > 0 else {
				fatalError("this should never happen")
			}
			#endif
			return match[matched] == byte
		}

		/// steps the matcher.
		internal mutating func step(isComplete:inout Bool) {
			matched += 1
			if matched == match.count {
				isComplete = true
			} else {
				isComplete = false
			}
		}

		internal mutating func reset() {
			matched = 0
		}
	}

	/// defines the separator that a given instance is searching for. also helps manage the state of this 'seek' exercise.
	private var separator:SeparatorInfo

	/// primary data buffer for the line parser to process and intake data.
	private var dataLogistics = BufferLogistics()

	/// the intake buffer pointer
	private var stepper:size_t = 0

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
	private static func processLine(separatorInfo:inout SeparatorInfo, storageBuffer:UnsafeBufferPointer<UInt8>, stepper:inout size_t, outputMode:Output) -> UnsafePointer<UInt8>? {
		stepLoop: while stepper < storageBuffer.count {
			if separatorInfo.doesMatch(storageBuffer[stepper]) {
				print("PROCESSLINE stepper \(stepper) - stepping through next byte \(String(describing:storageBuffer.baseAddress![stepper])) ( MATCHED )")
				var isMatchComplete = false
				separatorInfo.step(isComplete: &isMatchComplete)
				if isMatchComplete {
					separatorInfo.reset()
					let matchedLine = Array<UInt8>(UnsafeBufferPointer(start:storageBuffer.baseAddress!, count:stepper))
					switch outputMode {
					case .handler(let handler):
						handler(matchedLine)
					case .nasync(let nas):
						nas.yield(matchedLine)
					}
					defer {
						stepper = 0
					}
					return storageBuffer.baseAddress! + stepper + 1
				}
			} else {
				print("PROCESSLINE stepper \(stepper) - stepping through next byte \(String(describing:storageBuffer.baseAddress![stepper])) ( NO MATCH )")
				separatorInfo.reset()
			}
			stepper += 1
		}
		return nil
	}

	/// intakes the given amount of bytes, and processes them with the given handler.
	///	- parameter bytes: the amount of bytes to intake.
	///	- parameter writeHandler: the handler to write the bytes to the buffer.
	/// - throws: any error that the handler may throw.
	public mutating func intake(bytes:size_t, _ writeHandler:(UnsafeMutableBufferPointer<UInt8>) throws -> size_t) rethrows {
		try dataLogistics.intake(bytes:bytes, writeHandler)
		var alreadyFired:Int = 0
		defer {
			if alreadyFired != 0 {
				dataLogistics.rebase(offset:alreadyFired)
				stepper -= alreadyFired
			}
		}
		if separator.isEmpty() == false {
			dataLogistics.access { buff in
				var currentPtr = buff.baseAddress!
				var currentCount = buff.count
				seekLoop: while currentPtr < (buff.baseAddress! + buff.count) {
					if let newLineCompleted = Self.processLine(separatorInfo:&separator, storageBuffer:UnsafeBufferPointer(start:currentPtr, count:currentCount), stepper:&stepper, outputMode:outMode) {
						currentCount -= (newLineCompleted - currentPtr)
						currentPtr = newLineCompleted
					} else {
						break seekLoop
					}
				}
			}
		} else {
			dataLogistics.access { buff in
				let data = Array<UInt8>(UnsafeBufferPointer(start:buff.baseAddress!, count:buff.count))
				switch outMode {
				case .handler(let handler):
					handler(data)
				case .nasync(let nas):
					nas.yield(data)
				}
				alreadyFired = (buff.baseAddress! + buff.count) - buff.baseAddress!
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

	public consuming func finish() {
		dataLogistics.access { buff in
			if buff.count > 0 {
				let line = Array<UInt8>(UnsafeBufferPointer(start:buff.baseAddress, count:buff.count))
				switch outMode {
				case .handler(let handler):
					handler(line)
					handler(nil)
				case .nasync(let nas):
					nas.yield(line)
					nas.finish()
				}
			} else {
				switch outMode {
				case .handler(let handler):
					handler(nil)
				case .nasync(let nas):
					nas.finish()
				}
			}
		}
	}

	public consuming func finishDataloss() {
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