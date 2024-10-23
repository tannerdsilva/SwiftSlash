import Testing

@testable import SwiftSlashPThread
import __cswiftslash_threads

fileprivate struct PThreadWorkerTesterThing<A>:PThreadWork {
	typealias Argument = A
	typealias ReturnType = A
	private let inputArgument:Argument
	internal init(_ a:Argument) {
		self.inputArgument = a
	}
	mutating func pthreadWork() throws -> A {
		return inputArgument
	}
}

@Suite("SwiftSlashPThreadTests",
	.serialized
)
struct PThreadTests {

	@Test
	func testPthreadReturn() async throws {
		// try await withThrowingTaskGroup(of:(String, String).self, returning:Void.self, body: { group in
			for _ in 0..<50 {
				for i in 0..<10 {
					let randomString = String.random(length:56)
					let myString:String
					switch try await PThreadWorkerTesterThing<String>.run(randomString) {
					case .success(let s):
						myString = s
					case .failure(let e):
						throw e
					}
					#expect(randomString == myString)
				}
			}
		return
	}
	
	/*#if os(macOS)
	func testPthreadCancellation() async throws {
		let cancelExpect = XCTestExpectation(description:"PThread delay")
		let returnExpect = XCTestExpectation(description:"PThread delay")
		returnExpect.isInverted = true
		let freeExpect = XCTestExpectation(description:"PThread delay")
		final class MyTest {
			init(_ expect:XCTestExpectation) {
				self.expect = expect
			}
			let expect:XCTestExpectation
			deinit {
				expect.fulfill()
			}
		}
		let ltask = Task.detached {
			do {
				let runTask = try await SwiftSlashPThread.launch {
					_ = MyTest(freeExpect)
					sleep(5)
					returnExpect.fulfill()
				}
				try await Task.sleep(nanoseconds: 1_000_000_000)
				try runTask.cancel()
				switch await runTask.result() {
				case .success:
					XCTFail("Expected cancellation error")
				case .failure(let error):
					XCTAssertTrue(error is CancellationError)
				}
			} catch is CancellationError {
				cancelExpect.fulfill()
			}
		}
		await fulfillment(of:[cancelExpect, returnExpect, freeExpect], timeout: 2)
		await ltask.result
	}
	#endif*/
}


extension String {
	// Utility function to generate a random string of given length
	internal static func random(length: Int) -> String {
		let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+=-`~/?.>,<;:'\""
		return String((0..<length).map { _ in characters.randomElement()! })
	}
}
