import Testing

@testable import SwiftSlashPThread
import __cswiftslash_threads
@testable import SwiftSlashFuture

import func Foundation.sleep

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
internal struct PThreadTests {

	@Test("SwiftSlashPThread :: return values from pthreads")
	func testPthreadReturn() async throws {
		for _ in 0..<512 {
			let randomString = String.random(length:56)
			let myString:String?
			switch try await PThreadWorkerTesterThing<String>.run(randomString) {
			case .success(let s):
				myString = s
			case .failure(let e):
				throw e
			case .none:
				myString = nil
			}
			#expect(randomString == myString)
		}
	}

	fileprivate actor Expectation {
		private let isInverted:Bool
		private var didFulfill = false
		private let fulfillFuture = Future<Void, Never>()
		private let description:String
		fileprivate init(isInverted invert:Bool = false, description desc:String) {
			isInverted = invert
			description = desc
		}
		
		/// fulfills the expectation
		/// - returns: true if the expectation was fulfilled, false if it was already fulfilled.
		fileprivate func fulfill() -> Bool {
			guard didFulfill == false else {
				return false
			}
			didFulfill = true
			try! fulfillFuture.setSuccess(())
			return true
		}

		fileprivate func didFulfill(waitForSeconds secs:Double) async throws -> Bool {
			if didFulfill {
				return true
			}
			try await withThrowingTaskGroup(of:Bool.self, returning:Void.self) { tg in
				tg.addTask {
					try await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
					return false
				}
				tg.addTask { [ff = fulfillFuture] in
					_ = try await ff.result(throwingOnCurrentTaskCancellation:CancellationError.self, taskCancellationError: CancellationError())
					return true
				}
				do {
					consumeLoop: for try await _ in tg {
						break consumeLoop
					}
					tg.cancelAll()
				} catch {
					tg.cancelAll()
					throw error
				}
			}
			if isInverted {
				return !didFulfill
			} else {
				return didFulfill
			}
		}
	}
	
	@Test("SwiftSlashPThread :: cancellation of pthreads that are already in flight (with memory checks)")
	func testPthreadCancellation() async throws {
		// we do NOT expect the pthread to return.
		let returnExpect = Expectation(isInverted:true, description:"PThread delay")

		// we DO expect memoryspace to be freed as a result of the cancellation.
		let freeExpect = Expectation(description:"PThread delay")
		
		// this is a thing that holds an expectation and fulfills it when it is deinitialized.
		final class MyTest {
			init(_ expect:Expectation) {
				self.expect = expect
			}
			let expect:Expectation
			deinit {
				Task { [e = self.expect] in await e.fulfill() }
			}
		}

		// contains the asynchronous task that runs as a part of the test.
		let ltask = Task {

			let launchFuture = Future<Void, Never>()
			let cancelFuture = Future<Void, Never>()

			// launch the pthread that will be subject to cancellation testing.
			let runTask = try await SwiftSlashPThread.launch { [lf = launchFuture, cf = cancelFuture] in

				// declare a memory artifact within the pthread.
				_ = MyTest(freeExpect)

				try lf.setSuccess(())

				// wait for the cancelation to be set.
				try cf.blockingResult()!.get()

				// test for cancellation. this would usually be the end of the pthread.
				pthread_testcancel()

				// this should never fulfill.
				Task { await returnExpect.fulfill() }
			}

			// wait for the thread to launch.
			try await launchFuture.result()!.get()

			// cancel the thread
			try runTask.cancel()

			// set the cancellation future to success.
			try cancelFuture.setSuccess(())

			let gotReturn:Bool
			switch await runTask.workResult() {
			case .success:
				gotReturn = true
			case .failure(let error):
				#expect(error is CancellationError)
				gotReturn = false
			case .none:
				gotReturn = false
			}
			#expect(gotReturn == false)
		}

		// verify the results of the test.
		async let returnE = returnExpect.didFulfill(waitForSeconds: 2)
		async let freeE = freeExpect.didFulfill(waitForSeconds: 2)
		let returnR = try await returnE
		let freeR = try await freeE
		_ = try await ltask.value
		#expect(returnR == true)
		#expect(freeR == true)
	}
}


extension String {
	// utility function to generate a random string of given length
	internal static func random(length: Int) -> String {
		let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+=-`~/?.>,<;:'\""
		return String((0..<length).map { _ in characters.randomElement()! })
	}
}
