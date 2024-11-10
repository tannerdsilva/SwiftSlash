// internal tool to help extract the result from the future in a synchronous manner.
internal struct SyncResult:~Copyable {
	private var result:SuccessFailureCancel? = nil
	internal init() {}
	internal mutating func setResult(type:UInt8, pointer:UnsafeMutableRawPointer?) {
		result = .success(type, pointer)
	}
	internal mutating func setError(type:UInt8, pointer:UnsafeMutableRawPointer?) {
		result = .failure(type, pointer)
	}
	internal mutating func setCancel() {
		result = .cancel
	}
	internal consuming func consumeResult() -> SuccessFailureCancel? {
		return result
	}
}