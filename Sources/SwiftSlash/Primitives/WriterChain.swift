import CSwiftSlash

/// a writer chain. this is a structure that allows write operations to be chained atomically until a write can be performed.
internal class WriterChain {
	/// an error thrown by the writer chain.
	internal struct Error:Swift.Error {
		/// represents a value captured by errno.
		internal let systemErrorNumber:Int32
	}

	/// the primary writerchain primitive.
	private var wc:writerchainpair_t;

	/// the file handle to write to.
	private let fh:Int32

	/// initializes a new writer chain.
	/// - parameter fh: the file handle to write to.
	internal init(fh:Int32) {
		self.wc = wcp_init();
		self.fh = fh
	}
	
	/// writes the given data to the writer chain.
	/// - parameter data: the data to write.
	internal func write(_ data:inout [UInt8]) {
		wc_append(&self.wc, &data, data.count);
	}

	/// flushes the writer chain.
	/// - throws: an error if the flush failed unexpectedly.
	/// - note: this function will block until the flush is complete.
	internal func flush() throws {
		var errInt:Int32 = 0
		guard wc_flush(&self.wc, fh, &errInt) == true else {
			throw Error(systemErrorNumber:errInt)
		}
	}

	deinit {
		wcp_close(&self.wc);
	}
}