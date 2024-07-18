import XCTest
@testable import SwiftSlash
import SwiftSlashFuture

final class FutureTests: XCTestCase {
    func testSetSuccess() async throws {
        var future:Future<Int>? = Future<Int>()
        try future!.setSuccess(42)
        let result = await future!.result()
		switch result {
		case .success(let i):
			XCTAssertEqual(i, 42)
		default:
			XCTFail("Expected a success result")
		}
		future = nil
    }
    
	struct MyTestError:Swift.Error, Equatable {
		internal let code:Int
		internal let message:String
		static func == (lhs:MyTestError, rhs:MyTestError) -> Bool {
			return lhs.code == rhs.code && lhs.message == rhs.message
		}
	}
    func testSetFailure() async throws {
        let future = Future<Int>()
        let error = MyTestError(code: 42, message: "Test error")
		try future.setFailure(error)
        let result: Result<Int, any Error> = await future.result()
		switch result {
		case .failure(let e):
			XCTAssertEqual(e as! MyTestError, error)
		default:
			XCTFail("Expected a failure result")
		}
    }
    
    func testAwaitResult() async {
        let future = Future<String>()
        Task {
            try await Task.sleep(nanoseconds:1_000_000_000) // Simulating some asynchronous operation
            try future.setSuccess("Hello, World!")
        }
        let result = await future.result()
        switch result {
			case .success(let s):
				XCTAssertEqual(s, "Hello, World!")
			case .failure(let e):
				XCTFail("Expected a success result, got \(e)")
		}
	}
    
    // // Add more test cases as needed
    
    static var allTests = [
        ("testSetSuccess", testSetSuccess),
        ("testSetFailure", testSetFailure),
        ("testAwaitResult", testAwaitResult),
        // Add more test cases here
    ]
}
