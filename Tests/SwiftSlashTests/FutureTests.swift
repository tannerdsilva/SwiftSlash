import XCTest
@testable import SwiftSlash

final class FutureTests: XCTestCase {
    func testSetSuccess() {
        var future:Future<Int>? = Future<Int>()
        future!.setSuccess(42)
        let result = future!.blockForResult()
		switch result {
		case .success(let i):
			XCTAssertEqual(i, 42)
		default:
			XCTFail("Expected a success result")
		}
		// future = nil
    }
    
	struct MyTestError:Swift.Error, Equatable {
		internal let code:Int
		internal let message:String
		static func == (lhs:MyTestError, rhs:MyTestError) -> Bool {
			return lhs.code == rhs.code && lhs.message == rhs.message
		}
	}
    func testSetFailure() {
        let future = Future<Int>()
        let error = MyTestError(code: 42, message: "Test error")
		future.setFailure(error)
        let result = future.blockForResult()
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
            await Task.sleep(1) // Simulating some asynchronous operation
            future.setSuccess("Hello, World!")
        }
        let result = await future.awaitResult()
        switch result {
			case .success(let s):
				XCTAssertEqual(s, "Hello, World!")
			case .failure(let e):
				XCTFail("Expected a success result, got \(e)")
		}
	}
    
    // Add more test cases as needed
    
    static var allTests = [
        ("testSetSuccess", testSetSuccess),
        ("testSetFailure", testSetFailure),
        ("testAwaitResult", testAwaitResult),
        // Add more test cases here
    ]
}
