import __cswiftslash

#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

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
		/// the line parser will yield the parsed lines to the given continuation.
		case continuation(AsyncStream<[[UInt8]]>.Continuation)
		/// the line parser will handle the parsed lines with the given handler.
		case handler(([[UInt8]]) -> Void)
	}

	/// the line parser.
	private var lp:_cswiftslash_lineparser_t
	/// the output mode of the line parser.
	internal let outMode:Output

	/// initializes a new line parser.
	/// - parameters:
	/// 	- configuration: the configuration of the line parser.
	/// 	- output: the output mode of the line parser.
	internal init(configuration:Configuration, output:Output) {
		switch configuration {
		case .noSeparator:
			self.lp = _cswiftslash_lineparser_init(nil, 0);
			self.outMode = output
		case .withSeparator(let separator):
			self.lp = _cswiftslash_lineparser_init(separator, UInt8(separator.count));
			self.outMode = output
		}
	}

	/// handles the given data.
	///	- parameter data: the data to handle.
	internal mutating func handle(_ data:inout [UInt8]) {
		var result = [[UInt8]]()
		_cswiftslash_lineparser_intake(&self.lp, &data, data.count, { data, length in
			let asArray = Array<UInt8>(unsafeUninitializedCapacity: length, initializingWith: { buffer, count in
				memcpy(buffer.baseAddress!, data, length)
				count = length
			})
			result.append(asArray)
		})
		switch self.outMode {
		case .continuation(let continuation):
			continuation.yield(result)
		case .handler(let handler):
			handler(result)
		}
	}

	/// finishes the line parser. after calling this function, the line parser will not accept any more data. any attempts to call `handle(_:)` will result in undefined behavior.
	/// - parameter discardingBufferedData: whether or not to discard any buffered data. if this is set to `true`, any buffered data will be discarded. if this is set to `false`, any buffered data will be passed to the configured output.
	internal mutating func finish(discardingBufferedData:Bool = false) {
		if discardingBufferedData {
			_cswiftslash_lineparser_close_dataloss(&self.lp)
		} else {
			var buildItems = [[UInt8]]()
			_cswiftslash_lineparser_close(&self.lp, { data, length in
				let asArray = Array<UInt8>(unsafeUninitializedCapacity: length, initializingWith: { buffer, count in
					memcpy(buffer.baseAddress!, data, length)
					count = length
				})
			buildItems.append(asArray)
			})
			if buildItems.count > 0 {
				switch self.outMode {
				case .continuation(let continuation):
					continuation.yield(buildItems)
				case .handler(let handler):
					handler(buildItems)
				}
			}
		}
	}
}