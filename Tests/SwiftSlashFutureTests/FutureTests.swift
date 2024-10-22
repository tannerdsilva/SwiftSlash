import Testing

@testable import SwiftSlashFuture

@Suite("SwiftSlashFutureTests",
	.serialized
)
internal struct FutureTests {

	@Test func testSetSuccess() async throws {
        var future:Future<Int>? = Future<Int>()
        try future!.setSuccess(42)
		var foundResult:Int? = nil
        let result = await future!.result()
		switch result {
		case .success(let i):
			foundResult = i
		default:
			foundResult = nil
		}
		#expect(foundResult == 42)
		future = nil
    }
    
	struct MyTestError:Swift.Error, Equatable {
		internal let code:Int
		internal let message:String
		static func == (lhs:MyTestError, rhs:MyTestError) -> Bool {
			return lhs.code == rhs.code && lhs.message == rhs.message
		}
	}

	@Test func testSetFailure() async throws {
        let future = Future<Int>()
        let error = MyTestError(code: 42, message:"test error")
		try future.setFailure(error)
        let result: Result<Int, any Error> = await future.result()
		var foundError:MyTestError? = nil
		switch result {
		case .failure(let e):
			if let e = e as? MyTestError {
				foundError = e
			}
		default:
			break;
		}
		#expect(foundError == error)
    }
    
	@Test func testAwaitResult() async {
        var future:Future<String>? = Future<String>()
        Task {
            try await Task.sleep(nanoseconds:1_000_000_000) // simulating some asynchronous operation
            try future!.setSuccess("Hello, World!")
        }
        let result = await future!.result()
		var foundResult:String? = nil
        switch result {
			case .success(let s):
				foundResult = s
			case .failure(let e):
				foundResult = nil
		}
		#expect(foundResult == "Hello, World!")
		future = nil
	}
}
