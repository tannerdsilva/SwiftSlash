import __cswiftslash
import SwiftSlashNAsyncStream

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

	/// the line parser.
	private let lp:UnsafeMutablePointer<_cswiftslash_lineparser_t>
	/// the output mode of the line parser.
	private let outMode:Output

	public init(separator configuration:consuming [UInt8], nasync output:consuming NAsyncStream<[UInt8], Never>) {
		(lp, outMode) = configuration.withUnsafeBufferPointer { cPtr in 
			switch cPtr.count {
			case 0:
				let lp = UnsafeMutablePointer<_cswiftslash_lineparser_t>.allocate(capacity:1)
				lp.initialize(to:_cswiftslash_lineparser_init(nil, 0))
				return (lp, Output.nasync(output))
			default:
				let lp = UnsafeMutablePointer<_cswiftslash_lineparser_t>.allocate(capacity:1)
				lp.initialize(to:_cswiftslash_lineparser_init(cPtr.baseAddress!, UInt8(cPtr.count)))
				return (lp, Output.nasync(output))
			}
		}
	}

	public init(separator configuration:consuming [UInt8], handler output:consuming @escaping ([UInt8]?) -> Void) {
		(lp, outMode) = configuration.withUnsafeBufferPointer { cPtr in 
			switch cPtr.count {
			case 0:
				let lp = UnsafeMutablePointer<_cswiftslash_lineparser_t>.allocate(capacity:1)
				lp.initialize(to:_cswiftslash_lineparser_init(nil, 0))
				return (lp, Output.handler(output))
			default:
				let lp = UnsafeMutablePointer<_cswiftslash_lineparser_t>.allocate(capacity:1)
				lp.initialize(to:_cswiftslash_lineparser_init(cPtr.baseAddress!, UInt8(cPtr.count)))
				return (lp, Output.handler(output))
			}
		}
	}

	public mutating func intake(bytes:size_t, _ handler:(UnsafeMutablePointer<UInt8>) throws -> size_t) rethrows {
		try withUnsafePointer(to:outMode) { omPtr in
			let wptr = _cswiftslash_lineparser_intake_prepare(lp, bytes)
			let length = try handler(wptr)
			_cswiftslash_lineparser_intake_apply(lp, length)
			_cswiftslash_lineparser_intake_process(lp, { d, length, om in
				let line = Array<UInt8>(UnsafeBufferPointer(start:d, count:length))
				switch om.assumingMemoryBound(to:Output.self).pointee {
				case .handler(let handler):
					handler(line)
				case .nasync(let nas):
					nas.yield(line)
				}
			}, omPtr)
		}
	}

	/// handles the given data.
	///	- parameter data: the data to handle.
	public mutating func handle(_ data:consuming [UInt8]) {
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