import XCTest
@testable import SwiftSlash
import __cswiftslash
import SwiftSlashPThread
import Foundation

fileprivate struct PThreadWorkerTesterThing<A>:PThreadWork {
	typealias Argument = A
	typealias ReturnType = A
	private let inputArgument:Argument
	internal init(_ a:Argument) {
		self.inputArgument = a
	}
	mutating func run() throws -> A {
		return inputArgument
	}
}

class PThreadTests: XCTestCase {
    func testPthreadReturn() async throws {
		try await withThrowingTaskGroup(of:(String, String).self, returning:Void.self, body: { group in
			for ii in 0..<50 {
				for i in 0..<10 {
					group.addTask {
						let randomString = String.random(length:56)
						let myString:String
						switch try await PThreadWorkerTesterThing<String>.run(randomString) {
						case .success(let s):
							myString = s
						case .failure(let e):
							throw e
						}
						XCTAssertEqual(myString, randomString)
						return (randomString, myString)
					}
				}
				try await group.waitForAll()
			}
		})
		return
    }
	func pthreadCancellationTest() async throws {
		let cancelExpect = XCTestExpectation(description: "PThread delay")
		let returnExpect = XCTestExpectation(description: "PThread delay")
		let freeExpect = XCTestExpectation(description: "PThread delay")
		final class MyTest {
			init(_ expect:XCTestExpectation) {
				self.expect = expect
			}
			let expect:XCTestExpectation
			deinit {
				expect.fulfill()
			}
		}
		returnExpect.isInverted = true
		Task.detached {
			do {
				let runTask = Task.detached {
					try await pthreadRun {
						let myTest = MyTest(freeExpect)
						sleep(5)
						returnExpect.fulfill()
					}
				}
				try await Task.sleep(nanoseconds: 1_000_000_000)
				runTask.cancel()
				try await runTask.result.get().get()
			} catch is CancellationError {
				cancelExpect.fulfill()
			}
		}
		wait(for: [cancelExpect, returnExpect, freeExpect], timeout: 2)
	}
}