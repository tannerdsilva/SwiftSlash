import CSwiftSlash

/// a line parser.
/// takes raw bytes as input, and passes one or lines to the configured output.
internal struct LineParser {

	/// the configuration of the line parser.
	internal enum Configuration {
		/// no parsing. data will be passed as soon as it is provided by the kernel.
		case noSeparator
		/// parse lines separated by the given separator.
		case withSeparator(Bytes)
	}

	/// the output mode of the line parser.
	internal enum Output {
		/// the line parser will yield the parsed lines to the given continuation.
		// case continuation(AsyncStream<[Bytes]>.Continuation)
		/// the line parser will handle the parsed lines with the given handler.
		case handler(([Bytes]) -> Void)
	}

	/// the line parser.
	internal var lp:lineparser_t
	/// the output mode of the line parser.
	internal let outMode:Output

	/// initializes a new line parser.
	/// - parameters:
	/// 	- configuration: the configuration of the line parser.
	/// 	- output: the output mode of the line parser.
	internal init(configuration:Configuration, output:Output) {
		switch configuration {
		case .noSeparator:
			self.lp = lp_init(nil, 0);
			self.outMode = output
		case .withSeparator(let separator):
			self.lp = lp_init(separator, UInt8(separator.count));
			self.outMode = output
		}
	}

	/// handles the given data.
	/// - parameters:
	///		- data: the data to handle.
	internal mutating func handle(_ data:inout [UInt8]) {
		var result = [[UInt8]]()
		lp_intake(&self.lp, &data, data.count, { data, length in
			let asArray = Array<UInt8>(unsafeUninitializedCapacity: length, initializingWith: { buffer, count in
				memcpy(buffer.baseAddress!, data, length)
				count = length
			})
			result.append(asArray)
		})
		switch self.outMode {
		// case .continuation(let continuation):
		// 	continuation.yield(result)
		case .handler(let handler):
			handler(result)
		}
	}

	/// finishes the line parser. after calling this function, the line parser will not accept any more data. any attempts to call `handle(_:)` will result in undefined behavior.
	internal mutating func finish(discardingBufferedData:Bool = false) {
		if discardingBufferedData {
			lp_close_dataloss(&self.lp)
		} else {
			var buildItems = [Bytes]()
			lp_close(&self.lp, { data, length in
				let asArray = Array<UInt8>(unsafeUninitializedCapacity: length, initializingWith: { buffer, count in
					memcpy(buffer.baseAddress!, data, length)
					count = length
				})
				buildItems.append(asArray)
			})
			if buildItems.count > 0 {
				switch self.outMode {
				// case .continuation(let continuation):
				// 	continuation.yield(buildItems)
				case .handler(let handler):
					handler(buildItems)
				}
			}
		}
	}
}