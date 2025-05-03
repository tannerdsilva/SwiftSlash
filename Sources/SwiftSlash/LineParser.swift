/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_posix_helpers
import SwiftSlashFIFO

/// a line parser.
/// takes raw bytes as input, and passes one or lines to the configured output.
internal struct LineParser:~Copyable {

	/// the various types of output that the parser can use to produce lines.
	internal enum Output {
		/// pass the lines into a `NAsyncStream` for async consumption
		case nasync(FIFO<[LineOutput], Never>)
		/// pass the lines to a function closure
		case handler(([LineOutput]?) -> Void)
	}

	/// the type of output produced by the parser. output comes in the form of "lines" which is an array of bytes.
	internal typealias LineOutput = [UInt8]

	/// the primary storage buffer for incoming data.
	private var buffer:UnsafeMutablePointer<UInt8>
	/// the current capacity of the buffer.
	private var capacity:size_t
	/// the current number of bytes stored in the buffer.
	private var count:size_t = 0

	/// the byte pattern that the line parser will use to split incoming data into lines.
	private let separator:[UInt8]
	/// the output method for the parser.
	private let handler:Output

	/// - parameters:
	/// 	- separator: the byte‐pattern to split on (e.g. `Array("\r\n".utf8)`)
	/// 	- initialCapacity: starting buffer size; will grow as needed
	/// 	- output: the output method for the parser to use as it finds matches in the input stream
	internal init(separator sepArg: [UInt8], initialCapacity initCapArg:size_t, output handlerArg: consuming Output) {
		separator = sepArg
		capacity = max(initCapArg, sepArg.count)
		buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
		handler = handlerArg
	}
	
	internal init(separator sepArg:[UInt8], nasync output: FIFO<[LineOutput], Never>) {
		self.init(separator: sepArg, initialCapacity: 4_096, output: .nasync(output))
	}

	internal init(separator sepArg: [UInt8], handler handlerArg: @escaping ([LineOutput]?) -> Void) {
		self.init(separator: sepArg, initialCapacity: 4_096, output: .handler(handlerArg))
	}

	deinit {
		buffer.deallocate()
	}

	/// read up to `bytes` into the parser’s buffer (or consume it immediately if no separator).
	/// - parameters:
	/// 	- bytes: maximum number of bytes you will read
	/// 	- writeHandler: closure that gets a free `UnsafeMutableBufferPointer<UInt8>` of at most `bytes` capacity, writes into it **up to** that many bytes, and returns how many bytes were written (0 ⇒ EOF).
	/// - returns: the actual byte‐count read, so the caller can stop on `0`
	/// - throws: whatever `writeHandler` throws
	@discardableResult internal mutating func intake<E>(bytes: size_t, _ writeHandler: (UnsafeMutableBufferPointer<UInt8>) throws(E) -> size_t) throws(E) -> size_t where E: Swift.Error {
		// make room
		ensureCapacity(for: bytes)

		// write directly into our buffer
		let writePtr = buffer.advanced(by: count)
		let freeBuf  = UnsafeMutableBufferPointer(start:writePtr, count:Int(capacity - count))
		let readCount = try writeHandler(freeBuf)

		// if separator is empty, emit *exactly* this slice and return
		guard separator.isEmpty == false else {
			let slice = Array(UnsafeBufferPointer(start: writePtr, count: Int(readCount)))
			switch handler {
				case .nasync(let stream):
					stream.yield([slice])
				case .handler(let h):
					h([slice])
			}
			// do *not* accumulate or shift; each intake stands alone
			return readCount
		}
		// otherwise, normal split logic
		guard readCount > 0 else {
			// EOF or nothing read
			return readCount
		}
		count += readCount
		emitLinesIfAny()
		return readCount
	}

	/// convenience: consume a whole `[UInt8]` at once
	@discardableResult
	internal mutating func intake(_ data: consuming [UInt8]) -> size_t {
		return withUnsafeMutablePointer(to: &data) { ptr in
			intake(bytes: ptr.pointee.count) { buf in
				_ = buf.initialize(from: ptr.pointee)
				return ptr.pointee.count
			}
		}
	}

	/// emits any trailing bytes as a final slice, then signals end.
	internal mutating func finish() {
		// if there’s leftover *and* we have a separator, emit it
		if separator.isEmpty == false && count > 0 {
			let final = Array(UnsafeBufferPointer(start: buffer, count: Int(count)))
			switch handler {
				case .nasync(let stream):
					stream.yield([final])
					stream.finish()
				case .handler(let h):
					h([final])
					h(nil)
			}
			count = 0
		} else {
			// nothing to emit, just signal end
			switch handler {
				case .nasync(let stream):
					stream.finish()
				case .handler(let h):
					h(nil)
			}
		}
	}

	private mutating func ensureCapacity(for additional: size_t) {
		guard capacity >= count + additional else {
			var newCap = capacity * 2
			while count + additional > newCap {
				newCap *= 2
			}
			let newBuf: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: newCap)
			newBuf.update(from: buffer, count:count)
			buffer.deallocate()
			buffer = newBuf
			capacity = newCap
			return
		}
	}

	private mutating func emitLinesIfAny() {
		var lines = [LineOutput]()
		var lineStart = 0
		var pos = 0
		let sepCount = separator.count

		// scan for separator
		while sepCount > 0 && pos <= count - sepCount {
			var match = true
			for j in 0..<sepCount {
				if buffer[pos + j] != separator[j] {
					match = false
					break
				}
			}
			if match {
				let len = pos - lineStart
				let slice = Array(UnsafeBufferPointer(
					start: buffer.advanced(by: lineStart),
					count: len
				))
				lines.append(slice)
				lineStart = pos + sepCount
				pos = lineStart
			} else {
				pos += 1
			}
		}

		// shift leftover (incl. partial separator bytes)
		if lineStart > 0 {
			let leftover = Int(count) - lineStart
			if leftover > 0 {
				memmove(buffer, buffer.advanced(by: lineStart), leftover)
			}
			count = size_t(leftover)
		}

		if !lines.isEmpty {
			switch handler {
				case .nasync(let stream):
					stream.yield(lines)
				case .handler(let h):
					h(lines)
			}
		}
	}
}