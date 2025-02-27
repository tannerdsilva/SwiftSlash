/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Testing
@testable import SwiftSlashFuture

import __cswiftslash_future
import SwiftSlashContained

extension Tag {
	@Tag internal static var swiftSlashFuture:Self
}

extension Future {
	/// blocking wait for the result of the future. this is used only for unit testing.
	internal borrowing func blockingResult() -> Result<Produced, Failure>? {
		var getResult = SyncResult()
		withUnsafeMutablePointer(to:&getResult) { rptr in
			var memory = __cswiftslash_future_wait_t_init_struct()
			let waiter = __cswiftslash_future_t_wait_sync_register(prim, rptr, futureSyncResultHandler, futureSyncErrorHandler, futureSyncCancelHandler, &memory)
			guard waiter != nil else {
				return
			}
			__cswiftslash_future_t_wait_sync_block(prim, waiter!)
		}
		switch getResult.consumeResult()! {
			case .success(_, let res):
				return .success(Unmanaged<Contained<Produced>>.fromOpaque(res!).takeUnretainedValue().value())
			case .failure(_, let res):
				return .failure(Unmanaged<Contained<Failure>>.fromOpaque(res!).takeUnretainedValue().value())
			case .cancel:
				return nil
		}
	}
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
		private final class IntHeap:Equatable {
			private var value:Int
			private var conf:Confirmation?
			internal init(_ initialValue:Int, c:Confirmation) {
				value = initialValue
				conf = c
			}
			internal func getValue() -> Int {
				return value
			}
			internal func replaceConfirmation(_ newConf:Confirmation?) {
				conf = newConf
			}
			internal static func == (lhs:IntHeap, rhs:IntHeap) -> Bool {
				return lhs.value == rhs.value
			}
			deinit {
				conf?.confirm()
			}
		}
		private final class RandomTestError:@unchecked Sendable, Swift.Error, Equatable {
			private let c:Int
			private let m:String
			private let conf:UnsafeMutablePointer<Confirmation?>
			internal init(code:Int, message:String, confirmation:Confirmation?) {
				c = code
				m = message
				conf = UnsafeMutablePointer<Confirmation?>.allocate(capacity:1)
				conf.initialize(to:confirmation)
			}
			internal func replaceConfirmation(_ newConf:Confirmation?) {
				conf.pointee = newConf
			}
			internal static func == (lhs:RandomTestError, rhs:RandomTestError) -> Bool {
				return lhs.c == rhs.c && lhs.m == rhs.m
			}
			deinit {
				conf.pointee?.confirm()
				conf.deinitialize(count:1)
				conf.deallocate()
			}
		}

		private var future:Future<Int, Swift.Error> = Future<Int, Swift.Error>()

		@Test("SwiftSlashFuture :: test successful assignment with memory checks (random integer value)", .timeLimit(.minutes(1)))
		mutating internal func setSuccessWithMemoryChecks() async throws {
			try await confirmation("successful result value deallocation (with consume)", expectedCount:100) { resultValueDeallocatorCounter in
				var future:Future<IntHeap, Swift.Error> = Future<IntHeap, Swift.Error>()
				for _ in 0..<100 {
					let randomValue = IntHeap(Self.randomInt(), c:resultValueDeallocatorCounter)
					try future.setSuccess(randomValue)
					let result = try await future.result()!.get().getValue()
					#expect(result == randomValue.getValue())
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
					try await confirmation("testing for internal result value retention on direct pass", expectedCount:0) { resultValueHopeNoCountHere in
						try future.setSuccess(IntHeap(Self.randomInt(), c:resultValueHopeNoCountHere))
					}
					try await future.result()!.get().replaceConfirmation(resultValueDeallocatorCounter)
					future = Future<IntHeap, Swift.Error>()
				}
			}
		}

		@Test("SwiftSlashFuture :: test failure assignment with memory checks (random integer value)", .timeLimit(.minutes(1)))
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
					let randomMessage = Self.randomString(length: 20)
					try await confirmation("testing for internal result value retention on direct pass", expectedCount:0) { resultValueHopeNoCountHere in
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

		@Test("SwiftSlashFuture :: test async waiter with cancellation", .timeLimit(.minutes(1)))
		func testAsyncWaiterCancellation() async throws {
			let future = Future<Int, Never>()
			let resultHandler = await confirmation("test for correct dereferencing of @escaping handler references after firing", expectedCount:1) { cancelCounter in
				struct WhenDeinit:~Copyable {
					let cancelCounter:Confirmation
					init(_ c:Confirmation) {
						cancelCounter = c
					}
					deinit {
						cancelCounter.confirm()
					}
				}
				let cancelHandler = future.whenResult { [d = WhenDeinit(cancelCounter)] r in
					_ = d
					#expect(r == nil)
				}
				let resultHandler = future.whenResult { r in
					#expect(r != nil)
					switch r {
					case .success(let i):
						#expect(i == 5)
					default:
						break
					}
				}
				#expect(resultHandler != nil)
				#expect(cancelHandler != nil)
				#expect(future.cancelWaiter(cancelHandler!) == true)
				return resultHandler
			}

			try future.setSuccess(5)

			#expect(future.cancelWaiter(resultHandler!) == false)
		}

		@Test("SwiftSlashFuture :: test blocking waiter", .timeLimit(.minutes(1)))
		func testBlockingWaiter() throws {
			let future = Future<Int, Never>()
			Task { [f = future] in try f.setSuccess(5) }
			let result = future.blockingResult()!.get()
			#expect(result == 5)
		}
	}
}