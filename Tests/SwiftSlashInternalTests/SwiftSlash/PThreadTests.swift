/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Testing
@testable import SwiftSlashPThread

import __cswiftslash_threads
import SwiftSlashFuture
import func Foundation.sleep

extension Tag {
	@Tag internal static var swiftSlashPThread:Self
}

// a declaration of the pthread worker that will be used to test the pthreads.
fileprivate struct SimpleReturnWorker<A:Sendable>:PThreadWork {
	// the argument type of the pthread worker
	typealias Argument = A
	
	// the return type of the pthread worker
	typealias ReturnType = A
	
	// the input argument for the worker 
	private let ia:Argument
	
	// initialize the worker thing with a given argument value
	internal init(_ a:consuming Argument) {
		ia = a
	}
	
	// the pthread work that needs to be executed
	fileprivate mutating func pthreadWork() throws -> A {
		return ia
	}
}

extension SwiftSlashTests {
	@Suite("SwiftSlashPThreadTests",
		.serialized,
		.tags(.swiftSlashPThread)
	)
	internal struct PThreadTests {
		@Test("SwiftSlashPThread :: return values from pthreads", .timeLimit(.minutes(1)))
		func testPthreadReturn() async throws {
			for _ in 0..<512 {
				let randomString = String.random(length:56)
				let myString:String? = try await SimpleReturnWorker<String?>.run(randomString)!.get()
				#expect(randomString == myString)
			}
		}

		
		@Test("SwiftSlashPThread :: cancellation of pthreads that are already in flight (with memory checks)", .timeLimit(.minutes(1)))
		func testPthreadCancellation() async throws {
			try await confirmation("confirm that memoryspace is freed as a result of the cancellation", expectedCount:1) { freeConfirm in
				try await confirmation("confirm that the pthread does not return", expectedCount:0) { returnConfirm in
					// this is a thing that holds an expectation and fulfills it when it is deinitialized.
					final class MyTest {
						init(_ expect:Confirmation) {
							self.expect = expect
						}
						let expect:Confirmation
						deinit {
							expect.confirm()
						}
					}

					let launchFuture = Future<Void, Never>()
					let cancelFuture = Future<Void, Never>()
					
					// launch the pthread that will be subject to cancellation testing.
					let runTask = try SwiftSlashPThread.launch { [lf = launchFuture, cf = cancelFuture] in
						
						// declare a memory artifact within the pthread.
						_ = MyTest(freeConfirm)
						
						try lf.setSuccess(())
						
						// wait for the cancelation to be set.
						cf.blockingResult()!.get()
						
						// test for cancellation. this would usually be the end of the pthread.
						pthread_testcancel()
						
						// this should never fulfill.
						returnConfirm.confirm()
					}
					
					// wait for the thread to launch.
					await launchFuture.result()!.get()
					
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
			}
		}
	}
}


extension String {
	// utility function to generate a random string of given length
	internal static func random(length: Int) -> String {
		let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+=-`~/?.>,<;:'\""
		return String((0..<length).map { _ in characters.randomElement()! })
	}
}
