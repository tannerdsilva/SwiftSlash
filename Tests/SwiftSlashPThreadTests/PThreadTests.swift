import Testing

@testable import SwiftSlashPThread
import __cswiftslash_threads

// a declaration of the pthread worker that will be used to test the pthreads.
fileprivate struct PThreadWorkerTesterThing<A:Sendable>:PThreadWork {
	// the argument type of the pthread worker
	typealias Argument = A
	// the return type of the pthread worker
	typealias ReturnType = A
	private let inputArgument:Argument
	internal init(_ a:Argument) {
		self.inputArgument = a
	}
	fileprivate mutating func pthreadWork() throws -> A {
		return inputArgument
	}
}

@Suite("SwiftSlashPThreadTests")
struct PThreadTests {

	@Test("SwiftSlashPThread :: return values from pthreads")
	func testPthreadReturn() async throws {
		for _ in 0..<512 {
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

	fileprivate actor Expectation {
		private let isInverted:Bool
		private var didFulfill = false
		private init(isInverted invert:Bool = false) {
			isInverted = invert
		}

		fileprivate func fulfill() {
			didFulfill = true
		}

		fileprivate func didFulfill(waitForSeconds secs:Double) async throws -> Bool {
			if didFulfill {
				return true
			}
			try await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
			return didFulfill
		}
	}
	
	/*
	@Test("SwiftSlashPThread :: cancellation of pthreads that are already in flight")
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
	*/
}


extension String {
	// Utility function to generate a random string of given length
	internal static func random(length: Int) -> String {
		let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+=-`~/?.>,<;:'\""
		return String((0..<length).map { _ in characters.randomElement()! })
	}
}
