/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Testing
import Synchronization
import Foundation
import SwiftSlashPThread
@testable import SwiftSlashFuture

extension Tag {
	@Tag internal static var swiftSlashFuture:Self
}

extension SwiftSlashTests {
	@Suite("SwiftSlashFutureTests",
		.serialized,
		.tags(.swiftSlashFuture)
	)
	internal struct FutureTests {
		internal static func randomInt() -> Int {
			return Int.random(in:Int.min...Int.max)
		}
		internal static func randomString(length:Int) -> String {
			let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
			return String((0..<length).map({ _ in letters.randomElement()! }))
		}
		
		// IntHeap must be a class to test reference counting and deallocation
		private final class IntHeap:Sendable, Equatable {
			private let state:Mutex<(value:Int, conf:Confirmation?)>
			internal init(_ initialValue:Int, c:Confirmation) {
				state = Mutex((value: initialValue, conf: c))
			}
			internal func getValue() -> Int {
				return state.withLock({ $0.value })
			}
			internal func replaceConfirmation(_ newConf:Confirmation?) {
				state.withLock({ $0.conf = newConf })
			}
			internal static func == (lhs:IntHeap, rhs:IntHeap) -> Bool {
				return lhs.getValue() == rhs.getValue()
			}
			deinit {
				state.withLock({ $0.conf?.confirm() })
			}
		}
		
		private final class RandomTestError:Sendable, Swift.Error, Equatable {
			private let state:Mutex<(code:Int, message:String, conf:Confirmation?)>
			internal init(code:Int, message:String, confirmation:Confirmation?) {
				state = Mutex((code: code, message: message, conf: confirmation))
			}
			internal func replaceConfirmation(_ newConf:Confirmation?) {
				state.withLock({ $0.conf = newConf })
			}
			internal static func == (lhs:RandomTestError, rhs:RandomTestError) -> Bool {
				return lhs.state.withLock({ $0.code }) == rhs.state.withLock({ $0.code }) &&
					lhs.state.withLock({ $0.message }) == rhs.state.withLock({ $0.message })
			}
			deinit {
				state.withLock({ $0.conf?.confirm() })
				state.withLock({ $0.conf = nil })
			}
		}

		@Test("Future :: test successful assignment with memory checks (random integer value)", .timeLimit(.minutes(1)))
		mutating internal func setSuccessWithMemoryChecks() async throws {
			try await confirmation("successful result value deallocation (with consume)", expectedCount:100) { resultValueDeallocatorCounter in
				var future:Future<IntHeap, Swift.Error> = Future<IntHeap, Swift.Error>()
				for _ in 0..<100 {
					let randomValue = IntHeap(Self.randomInt(), c:resultValueDeallocatorCounter)
					#expect(future.hasResult() == false)
					try future.setSuccess(randomValue)
					let result = try await future.result()!.get().getValue()
					#expect(result == randomValue.getValue())
					#expect(future.hasResult() == true)
					future = Future<IntHeap, Swift.Error>()
				}
			}
			try await confirmation("successful result value deallocation (no consume)", expectedCount:100) { resultValueDeallocatorCounter in
				var future:Future<IntHeap, Swift.Error> = Future<IntHeap, Swift.Error>()
				for _ in 0..<100 {
					let randomValue = IntHeap(Self.randomInt(), c:resultValueDeallocatorCounter)
					try future.setSuccess(randomValue)
					future = Future<IntHeap, Swift.Error>()
				}
			}
			
			// test a loop of 100 successful results with the result NOT being consumed
			try await confirmation("successful result value deallocation (direct pass)", expectedCount:100) { resultValueDeallocatorCounter in
				var future:Future<IntHeap, Swift.Error> = Future<IntHeap, Swift.Error>()
				for _ in 0..<100 {
					_ = try await confirmation("testing for internal result value retention on direct pass", expectedCount:0) { resultValueHopeNoCountHere in
						try future.setSuccess(IntHeap(Self.randomInt(), c:resultValueHopeNoCountHere))
					}
					try await future.result()!.get().replaceConfirmation(resultValueDeallocatorCounter)
					future = Future<IntHeap, Swift.Error>()
				}
			}
		}

		@Test("Future :: test failure assignment with memory checks (random integer value)", .timeLimit(.minutes(1)))
		mutating func testSetFailureWithRandomErrors() async throws {
			try await confirmation("successful result value deallocation (with consume)", expectedCount:100) { resultValueDeallocatorCounter in
				var future:Future<IntHeap, RandomTestError> = Future<IntHeap, RandomTestError>()
				for _ in 0..<100 {
					let error = RandomTestError(code: Self.randomInt(), message: Self.randomString(length: 20), confirmation:resultValueDeallocatorCounter)
					try future.setFailure(error)
					let result = await future.result()!
					#expect(result == Result.failure(error))
					future = Future<IntHeap, RandomTestError>()
				}
			}

			try await confirmation("successful result value deallocation (with consume)", expectedCount:100) { resultValueDeallocatorCounter in
				var future:Future<IntHeap, RandomTestError> = Future<IntHeap, RandomTestError>()
				for _ in 0..<100 {
					let error = RandomTestError(code:Self.randomInt(), message:Self.randomString(length:20), confirmation:resultValueDeallocatorCounter)
					try future.setFailure(error)
					future = Future<IntHeap, RandomTestError>()
				}
			}

			try await confirmation("successful result value deallocation (with consume)", expectedCount:100) { resultValueDeallocatorCounter in
				var future:Future<IntHeap, RandomTestError> = Future<IntHeap, RandomTestError>()
				for _ in 0..<100 {
					let randomInt = Self.randomInt()
					let randomMessage = Self.randomString(length:20)
					_ = try await confirmation("testing for internal result value retention on direct pass", expectedCount:0) { resultValueHopeNoCountHere in
						try future.setFailure(RandomTestError(code:randomInt, message:randomMessage, confirmation:resultValueHopeNoCountHere))
					}
					let result = await future.result()!
					#expect(result == Result.failure(RandomTestError(code:randomInt, message:randomMessage, confirmation:nil)))
					guard case .failure(let e) = result else {
						fatalError("should never happen")
					}
					e.replaceConfirmation(resultValueDeallocatorCounter)
					future = Future<IntHeap, RandomTestError>()
				}
			}
		}

		@Test("Future :: test async waiter with cancellation", .timeLimit(.minutes(1)))
		func testAsyncWaiterCancellation() async throws {
			// test dropping the future while a `whenResult` callback is pending.
			// this verifies that deinit correctly resumes waiters with nil and drops references.
			await confirmation("test for correct dereferencing of @escaping handler references after dropping future", expectedCount:1) { cancelCounter in
				struct WhenDeInit:~Copyable {
					let cancelCounter:Confirmation
					init(_ c:Confirmation) {
						cancelCounter = c
					}
					deinit {
						cancelCounter.confirm()
					}
				}
				let future = Future<Int, Never>()
				_ = future.whenResult { [d = WhenDeInit(cancelCounter)] r in
					_ = d
					#expect(r == nil)
				}
				// future goes out of scope here, triggering deinit which cancels waiters with nil
			}

			// test task cancellation
			let future2 = Future<Int, Never>()
			let task = Task<Bool, Never> {
				do {
					_ = try await future2.result(throwing:CancellationError.self, onCurrentTaskCancellation:CancellationError())
					return false
				} catch {
					return true
				}
			}
			task.cancel()
			let didThrow = await task.value
			#expect(didThrow == true)
			
			// ensure future2 can still be set without crashing, though the result is ignored by the cancelled task
			try future2.setSuccess(5)
		}
		
		@Test("Future :: test whenResult synchronous firing", .timeLimit(.minutes(1)))
		func testWhenResultSynchronous() async throws {
			let future = Future<Int, Never>()
			try future.setSuccess(10)
			
			await confirmation("whenResult fires synchronously", expectedCount: 1) { syncFire in
				let handlerID = future.whenResult { result in
					syncFire.confirm()
					#expect(result != nil)
					#expect(result!.get() == 10)
				}
				#expect(handlerID == nil)
			}
		}

		@Test("Future :: test blocking waiter", .timeLimit(.minutes(1)))
		func testBlockingWaiter() throws {
			let future = Future<Int, Never>()
			Task { [f = future] in try f.setSuccess(5) }
			let result = future.waitSynchronously().wait()!.get()
			#expect(result == 5)
		}

		@Test("Future :: test blocking waiter already resolved", .timeLimit(.minutes(1)))
		func testBlockingWaiterAlreadyResolved() throws {
			let future = Future<Int, Never>()
			try future.setSuccess(7)
			let result = future.waitSynchronously().wait()!.get()
			#expect(result == 7)
		}

		@Test("Future :: test blocking waiter cancelled", .timeLimit(.minutes(1)))
		@SwiftSlashPThreadBackedExecutor func testBlockingWaiterCancelled() throws {
			let future = Future<Int, Never>()
			let resultTool = future.waitSynchronously()
			Task.detached { [f = future] in 
				// wait two seconds
				try await Task.sleep(nanoseconds: 2 * 1_000_000_000) // 2s
				#expect(f.cancelWaiter(resultTool.uid) == true)
			}
			let capResult = resultTool.wait()
			#expect(capResult == nil)
			try future.setSuccess(10) // ensure future can still be set without crashing
			#expect(future.waitSynchronously().wait()!.get() == 10)
		}

		@Test("Future :: test code block waiter cancelled", .timeLimit(.minutes(1)))
		func testCodeBlockWaiterCancelled() async throws {
			let future = Future<Int, Never>()
			await confirmation("confirm that the waiter is cancelled", expectedCount: 1) { cancelConfirm in
				let handlerID = future.whenResult { result in
					cancelConfirm.confirm()
					#expect(result == nil)
				}
				#expect(handlerID != nil)
				#expect(future.cancelWaiter(handlerID!) == true)
			}
		}

		@Test("Future :: test cancelling a factory fresh future", .timeLimit(.minutes(1)))
		func testCancellingVirginFuture() async throws {
			let future = Future<Int, Never>()
			#expect(future.cancelWaiter(123456789) == false) // should be a no-op, but not crash
			try future.setSuccess(42) // ensure future can still be set without crashing
			#expect(future.cancelWaiter(24680) == false) // should be a no-op, but not crash
		}

		// MARK: - Torture Tests

		@Test("Future :: torture test high concurrency resolvers", .timeLimit(.minutes(1)))
		func testHighConcurrencyResolvers() async throws {
			let future = Future<Int, Never>()
			let successCount = Atomic<Int>(0)
			let errorCount = Atomic<Int>(0)
			await withTaskGroup(of: Result<Bool, Never>.self) { group in
				for i in 0..<100 {
					group.addTask {
						do {
							try future.setSuccess(i)
							return .success(true)
						} catch {
							return .success(false)
						}
					}
				}
				for await result in group {
					if result == .success(true) {
						successCount.add(1, ordering: .acquiring)
					} else {
						errorCount.add(1, ordering: .acquiring)
					}
				}
			}
			
			#expect(successCount.load(ordering: .acquiring) == 1)
			#expect(errorCount.load(ordering: .acquiring) == 99)
			
			let result = await future.result()!.get()
			#expect(result >= 0 && result < 100)
		}

		@Test("Future :: torture test high concurrency waiters", .timeLimit(.minutes(1)))
		func testHighConcurrencyWaiters() async throws {
			let future = Future<Int, Never>()
			let expectedValue = 42
			
			await withTaskGroup(of: Int?.self) { group in
				for _ in 0..<100 {
					group.addTask {
						return await future.result()?.get()
					}
				}
				
				// give the waiters a moment to register
				try! await Task.sleep(nanoseconds: 100_000_000)
				try! future.setSuccess(expectedValue)
				
				for await result in group {
					#expect(result == expectedValue)
				}
			}
		}

		@Test("Future :: torture test high concurrency sync waiters", .timeLimit(.minutes(1)))
		func testHighConcurrencySyncWaiters() async throws {
			func waitForAllThreads(_ threads: [Running<GenericPThread<Void>>]) throws {
				for t in threads {
					try t.joinSync()
				}
			}
			let future = Future<Int, Never>()
			let expectedValue = 99
			let threadsCount = 100
			let expectation = Atomic<Int>(0)

			var runningThreads: [Running<GenericPThread<Void>>] = []
			for _ in 0..<threadsCount {
				runningThreads.append(try SwiftSlashPThread.launch {
					let result = future.waitSynchronously()
					if result.wait()?.get() == expectedValue {
						expectation.add(1, ordering: .sequentiallyConsistent)
					}
				})
			}
			
			// give the threads time to block on the semaphore
			try await Task.sleep(nanoseconds: 200_000_000)
			try future.setSuccess(expectedValue)
			
			try waitForAllThreads(runningThreads)
			
			#expect(expectation.load(ordering: .sequentiallyConsistent) == threadsCount)
		}

		@Test("Future :: torture test multiple whenResult callbacks", .timeLimit(.minutes(1)))
		func testMultipleWhenResultCallbacks() async throws {
			let future = Future<Int, Never>()
			let expectedValue = 123
			
			try await confirmation("all callbacks fired", expectedCount: 50) { confirm in
				for _ in 0..<50 {
					_ = future.whenResult { result in
						#expect(result?.get() == expectedValue)
						confirm()
					}
				}
				try future.setSuccess(expectedValue)
			}
		}

		@Test("Future :: torture test drop future with many whenResult callbacks", .timeLimit(.minutes(1)))
		func testDropFutureWithManyWhenResult() async throws {
			await confirmation("all callbacks cancelled on drop", expectedCount: 100) { confirm in
				struct WhenDeInit: ~Copyable {
					let cancelCounter: Confirmation
					init(_ c: Confirmation) { cancelCounter = c }
					deinit { cancelCounter.confirm() }
				}
				
				let future = Future<Int, Never>()
				for _ in 0..<100 {
					_ = future.whenResult { [d = WhenDeInit(confirm)] r in
						_ = d
						#expect(r == nil)
					}
				}
				// future goes out of scope here, triggering deinit which cancels waiters with nil
			}
		}

		@Test("Future :: torture test stress result with cancellation", .timeLimit(.minutes(2)))
		func testStressResultWithCancellation() async throws {
			let future = Future<Int, Never>()
			let expectedValue = 777
			let totalTasks = 100
			let cancelTasks = totalTasks / 2
			
			var tasks: [Task<Bool, Never>] = []
			for i in 0..<totalTasks {
				let task = Task<Bool, Never> {
					try? await Task.sleep(nanoseconds:UInt64.random(in:1...4) * 1_000_000_000) // random sleep between 1 and 4 seconds
					do {
						let res = try await future.result(throwing: CancellationError.self, onCurrentTaskCancellation: CancellationError())
						return res?.get() == expectedValue
					} catch is CancellationError {
						return false // threw cancellation
					} catch {
						return false
					}
				}
				if i < cancelTasks {
					task.cancel()
				}
				tasks.append(task)
			}

			try future.setSuccess(expectedValue)
			
			var successCount = 0
			var cancelCount = 0
			for task in tasks {
				let result = await task.value
				if result {
					successCount += 1
				} else {
					cancelCount += 1
				}
			}
			
			#expect(successCount == totalTasks - cancelTasks)
			#expect(cancelCount == cancelTasks)
		}
	}
}
