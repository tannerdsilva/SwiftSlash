import __cswiftslash
import SwiftSlashNAsyncStream

/// a line parser.
/// takes raw bytes as input, and passes one or lines to the configured output.
internal struct LineParser:~Copyable {

	/// the configuration of the line parser.
	internal enum Configuration {
		/// no parsing. data will be passed as soon as it is provided by the kernel.
		case noSeparator
		/// parse lines separated by the given separator.
		case withSeparator([UInt8])
	}

	/// the output mode of the line parser.
	internal enum Output {
		/// the line parser will handle the parsed lines with the given handler.
		case handler(([UInt8]?) -> Void)
		/// the line parser will yield the parsed lines to the given nasyncstream.
		case nasync(NAsyncStream<[UInt8], Never>)
	}

	/// the line parser.
	private let lp:UnsafeMutablePointer<_cswiftslash_lineparser_t>
	/// the output mode of the line parser.
	internal let outMode:Output

	/// initializes a new line parser.
	/// - parameters:
	/// 	- configuration: the configuration of the line parser.
	/// 	- output: the output mode of the line parser.
	internal init(configuration:Configuration, output:Output) {
		switch configuration {
		case .noSeparator:
			lp = UnsafeMutablePointer<_cswiftslash_lineparser_t>.allocate(capacity:1)
			lp.initialize(to:_cswiftslash_lineparser_init(nil, 0))
			self.outMode = output
		case .withSeparator(let separator):
			lp = UnsafeMutablePointer<_cswiftslash_lineparser_t>.allocate(capacity:1)
			lp.initialize(to:_cswiftslash_lineparser_init(separator, UInt8(separator.count)))
			self.outMode = output
		}
	}

	internal mutating func prepare(bytes:size_t, _ handler:(UnsafeMutablePointer<UInt8>) throws -> size_t) rethrows {
		try withUnsafePointer(to:outMode) { omPtr in
			let wptr = _cswiftslash_lineparser_intake_prepare(lp, bytes)
			let length = try handler(wptr)
			_cswiftslash_lineparser_intake_apply(lp, length)
		}
	}

	/// handles the given data.
	///	- parameter data: the data to handle.
	internal mutating func handle(_ data:consuming [UInt8]) {
		withUnsafePointer(to:outMode) { omPtr in
			data.withUnsafeBufferPointer { buffer in
				let wptr = _cswiftslash_lineparser_intake_prepare(lp, buffer.count)
				memcpy(wptr, buffer.baseAddress!, buffer.count)
				_cswiftslash_lineparser_intake_apply(lp, buffer.count)
				_cswiftslash_lineparser_intake_process(lp, { d, length, om in
					let line = Array<UInt8>(unsafeUninitializedCapacity: length, initializingWith: { buffer, count in
						memcpy(buffer.baseAddress!, d, length)
						count = length
					})
					switch om.assumingMemoryBound(to:Output.self).pointee {
					case .handler(let handler):
						handler(line)
					case .nasync(let nas):
						nas.yield(line)
					}
				}, omPtr)
			}
		}
	}

	/// finishes the line parser. after calling this function, the line parser will not accept any more data. any attempts to call `handle(_:)` will result in undefined behavior.
	/// - parameter discardingBufferedData: whether or not to discard any buffered data. if this is set to `true`, any buffered data will be discarded. if this is set to `false`, any buffered data will be passed to the configured output.
	deinit {
		withUnsafePointer(to:outMode) { om in
			_cswiftslash_lineparser_close(lp, { data, length, om in
				let line = [UInt8](UnsafeBufferPointer(start:data, count:length))
				switch om.assumingMemoryBound(to:Output.self).pointee {
				case .handler(let handler):
					handler(line)
				case .nasync(let nas):
					nas.yield(line)
				}
			}, om)
		}
		lp.deinitialize(count:1)
		lp.deallocate()
	}
}