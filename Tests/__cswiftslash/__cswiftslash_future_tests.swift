/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Testing

@testable import __cswiftslash_future

import __cswiftslash_auint8

@Suite("__cswiftslash_future",
	.serialized
)
internal struct FutureTests {
	// MARK: C Harness
	fileprivate final class Harness:@unchecked Sendable {

		fileprivate enum Result:@unchecked Sendable, Equatable {
			case success(UInt8, UnsafeMutableRawPointer?)
			case failure(UInt8, UnsafeMutableRawPointer?)

			fileprivate func type() -> UInt8 {
				switch self {
					case .success(let type, _):
						return type
					case .failure(let type, _):
						return type
				}
			}
			
			fileprivate func pointer() -> UnsafeMutableRawPointer? {
				switch self {
					case .success(_, let pointer):
						return pointer
					case .failure(_, let pointer):
						return pointer
				}
			}
		}
		private let futurePtr:UnsafeMutablePointer<__cswiftslash_future_t>
		fileprivate init() {
			self.futurePtr = __cswiftslash_future_t_init()
		}

		fileprivate func cancel() -> Bool {
			__cswiftslash_future_t_broadcast_cancel(self.futurePtr)
		}

		fileprivate func waitAsync() async throws -> Result? {
			var resultStore:(pthread_t, Result?)? = nil
			let asyncResultMemory = UnsafeMutablePointer<AsyncResult>.allocate(capacity:1)
			asyncResultMemory.initialize(to:AsyncResult(resultHandler: { resType, resPtr in
				resultStore = (pthread_self(), .success(resType, resPtr))
			}, errorHandler: { errType, errPtr in
				resultStore = (pthread_self(), .failure(errType, errPtr))
			}, cancelHandler: {
				resultStore = (pthread_self(), nil)
			}))
			let keyThing = __cswiftslash_future_t_wait_async(self.futurePtr, asyncResultMemory, Self.futureAsyncResultHandler, Self.futureAsyncErrorHandler, Self.futureAsyncCancelHandler)
			try await withTaskCancellationHandler(operation: { 
				try await withUnsafeThrowingContinuation({ [asm = asyncResultMemory.pointee] (cont:UnsafeContinuation<Void, Swift.Error>) in
					let apid = asm.auditPID()
					guard pthread_equal(apid, resultStore!.0) != 0 else {
						cont.resume(throwing: UnexpectedAsyncronousThreading())
						return
					}
					cont.resume()
				})
			}, onCancel: {
				__cswiftslash_future_t_wait_async_invalidate(self.futurePtr, keyThing)
			})
			return resultStore!.1
		}
		internal func broadcastResultValue(resType: UInt8, resVal:UnsafeMutableRawPointer?) -> Bool {
			return __cswiftslash_future_t_broadcast_res_val(self.futurePtr, resType, resVal)
		}
		internal func broadcastErrorValue(errType: UInt8, errVal:UnsafeMutableRawPointer?) -> Bool {
			return __cswiftslash_future_t_broadcast_res_throw(self.futurePtr, errType, errVal)
		}

		fileprivate struct UnexpectedAsyncronousThreading:Swift.Error {}
		private final class AsyncResult {

			private var expectedPID:pthread_t? = nil
			
			private var istate = pthread_mutex_t()

			private var mutex:pthread_mutex_t = pthread_mutex_t()
			private var mlocked:__cswiftslash_atomic_uint8_t
			
			private var resultHandler:Optional<(UInt8, UnsafeMutableRawPointer?) -> Void>
			private var errorHandler:Optional<(UInt8, UnsafeMutableRawPointer?) -> Void>
			private var cancelHandler:Optional<() -> Void>

			fileprivate init(resultHandler rh:@escaping((UInt8, UnsafeMutableRawPointer?) -> Void), errorHandler eh:@escaping((UInt8, UnsafeMutableRawPointer?) -> Void), cancelHandler ch:@escaping(() -> Void)) {
				resultHandler = rh
				errorHandler = eh
				cancelHandler = ch
				mlocked = __cswiftslash_auint8_init(1)
				pthread_mutex_init(&mutex, nil)
				pthread_mutex_lock(&mutex)
				pthread_mutex_init(&istate, nil)
			}

			fileprivate func setResult(type:UInt8, pointer result:__cswiftslash_optr_t?) {
				pthread_mutex_lock(&istate)
				resultHandler?(type, result)
				var expectedLockVal:UInt8 = 1
				if __cswiftslash_auint8_compare_exchange_weak(&mlocked, &expectedLockVal, 0) {
					pthread_mutex_unlock(&mutex)
				}
				expectedPID = pthread_self()
				resultHandler = nil
				errorHandler = nil
				cancelHandler = nil
				pthread_mutex_unlock(&istate)
			}

			fileprivate func setError(type:UInt8, pointer error:__cswiftslash_optr_t?) {
				pthread_mutex_lock(&istate)
				errorHandler?(type, error)
				var expectedLockVal:UInt8 = 1
				if __cswiftslash_auint8_compare_exchange_weak(&mlocked, &expectedLockVal, 0) {
					pthread_mutex_unlock(&mutex)
				}
				expectedPID = pthread_self()
				resultHandler = nil
				errorHandler = nil
				cancelHandler = nil
				pthread_mutex_unlock(&istate)
			}

			fileprivate func setCancel(contextPtr:UnsafeMutableRawPointer?) {
				pthread_mutex_lock(&istate)
				cancelHandler?()
				var expectedLockVal:UInt8 = 1
				if __cswiftslash_auint8_compare_exchange_weak(&mlocked, &expectedLockVal, 0) {
					pthread_mutex_unlock(&mutex)
				}
				expectedPID = pthread_self()
				resultHandler = nil
				errorHandler = nil
				cancelHandler = nil
				pthread_mutex_unlock(&istate)
			}

			fileprivate func auditPID() -> pthread_t {
				pthread_mutex_lock(&istate)
				if cancelHandler != nil {
					pthread_mutex_unlock(&istate)
					pthread_mutex_lock(&mutex)
					pthread_mutex_lock(&istate)
					pthread_mutex_unlock(&mutex)
					__cswiftslash_auint8_store(&mlocked, 0)
				}
				let ret = expectedPID!
				pthread_mutex_unlock(&istate)
				return ret
			}

			deinit {
				pthread_mutex_lock(&istate)
				if __cswiftslash_auint8_load(&mlocked) == 1 {
					pthread_mutex_unlock(&mutex)
				}
				pthread_mutex_unlock(&istate)
				pthread_mutex_destroy(&mutex)
			}
		}

		private static let futureAsyncResultHandler:__cswiftslash_future_result_val_handler_f = { resType, resPtr, ctxPtr in
			ctxPtr?.assumingMemoryBound(to:AsyncResult.self).pointee.setResult(type:resType, pointer:resPtr)
		}
		private static let futureAsyncErrorHandler:__cswiftslash_future_result_err_handler_f = { errType, errPtr, ctxPtr in
			ctxPtr?.assumingMemoryBound(to:AsyncResult.self).pointee.setError(type:errType, pointer:errPtr)
		}
		private static let futureAsyncCancelHandler:__cswiftslash_future_result_cncl_handler_f = { ctxPtr in
			ctxPtr?.assumingMemoryBound(to:AsyncResult.self).pointee.setCancel(contextPtr:ctxPtr)
		}

		private struct SyncResult {
			fileprivate struct NoResultAvailable:Swift.Error {}
			private enum ResultOrNoResult {
				case noResult
				case result(Result?)
			}
			private var ron:ResultOrNoResult = .noResult
			private var assPT:pthread_t? = nil
			fileprivate init() {}
			fileprivate mutating func setResult(type:UInt8, pointer resultPtr:__cswiftslash_optr_t?) {
				ron = .result(.success(type, resultPtr))
				assPT = pthread_self()
			}
			fileprivate mutating func setError(type:UInt8, pointer errorPtr:__cswiftslash_optr_t?) {
				ron = .result(.failure(type, errorPtr))
				assPT = pthread_self()
			}
			fileprivate mutating func setNil() {
				ron = .result(nil)
				assPT = pthread_self()
			}
			fileprivate func getResult() throws -> (Result?, pthread_t) {
				switch ron {
					case .noResult:
						throw NoResultAvailable()
					case .result(let res):
						return (res, assPT!)
				}
			}
		}

		internal struct UnexpectedSyncronousThreading:Swift.Error {}
		internal func waitSync() throws -> Result? {
			let mytid = pthread_self()
			var srInstance = SyncResult()
			withUnsafeMutablePointer(to:&srInstance) { srInstance in
				__cswiftslash_future_t_wait_sync(futurePtr, srInstance, Self.futureSyncResultHandler, Self.futureSyncErrorHandler, Self.futureSyncCancelHandler)
			}
			let getr = try srInstance.getResult()
			guard pthread_equal(mytid, getr.1) != 0 else {
				throw UnexpectedSyncronousThreading()
			}
			return getr.0
		}

		private static let futureSyncResultHandler:__cswiftslash_future_result_val_handler_f = { resType, resPtr, ctxPtr in
			// pass the result into the SyncResult instance.
			ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setResult(type:resType, pointer:resPtr)
		}

		private static let futureSyncErrorHandler:__cswiftslash_future_result_err_handler_f = { errType, errPtr, ctxPtr in
			// pass the error into the SyncResult instance.
			ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setError(type:errType, pointer:errPtr)
		}

		private static let futureSyncCancelHandler:__cswiftslash_future_result_cncl_handler_f = { ctxPtr in
			// pass the cancellation into the SyncResult instance.
			ctxPtr!.assumingMemoryBound(to:SyncResult.self).pointee.setNil()
		}
	}

	// MARK: - Core Sync Tests
	@Test("__cswiftslash_future :: core :: sync result")
	func testWaitSyncForResult() async throws {
		try await withThrowingTaskGroup(of:Void.self, returning:Void.self) { tg in
			let future = Harness()
			tg.addTask {
				let data = UnsafeMutableRawPointer(bitPattern: 0x1234)!
				#expect(future.broadcastResultValue(resType: 1, resVal: data) == true)
			}
			// wait synchronously for the future to complete
			let result = try future.waitSync()
			
			var foundType:UInt8? = nil
			var foundValue:UnsafeMutableRawPointer? = nil

			// check that the result was received
			switch result {
			case .success(let type, let value):
				foundType = type
				foundValue = value
			default:
				break
			}

			#expect(foundType == 1)
			#expect(foundValue == UnsafeMutableRawPointer(bitPattern: 0x1234))
		}
	}

	@Test("__cswiftslash_future :: core :: sync error")
	func testWaitSyncForError() async throws {
		try await withThrowingTaskGroup(of:Void.self, returning:Void.self) { tg in
			let future = Harness()
			tg.addTask {
				let errorData = UnsafeMutableRawPointer(bitPattern: 0x4321)!
				#expect(future.broadcastErrorValue(errType: 2, errVal: errorData) == true)
			}
			// wait synchronously for the future to complete
			let result = try future.waitSync()
			
			var foundType:UInt8? = nil
			var foundValue:UnsafeMutableRawPointer? = nil

			// check that the error was received
			switch result {
			case .failure(let type, let value):
				foundType = type
				foundValue = value
			default:
				break
			}

			#expect(foundType == 2)
			#expect(foundValue == UnsafeMutableRawPointer(bitPattern: 0x4321))
		}
	}

	@Test("__cswiftslash_future :: core :: sync cancel")
	func testSyncWaiterCancellation() async throws {
		let future = Harness()
		try await withThrowingTaskGroup(of:FutureTests.Harness.Result?.self) { tg in
			tg.addTask {
				return try future.waitSync()
			}
			#expect(future.cancel() == true)
			var i = 0
			for try await result in tg {
				#expect(result == nil)
				i += 1
			}
			#expect(i == 1)
		}
	}

	// MARK: - Core Async Tests
	// test async waiters receiving results
	@Test("__cswiftslash_future :: core :: async result")
	func testWaitAsyncForResult() async throws {
		try await withThrowingTaskGroup(of:Void.self, returning:Void.self) { tg in
			let future = Harness()
			tg.addTask {
				let data = UnsafeMutableRawPointer(bitPattern: 0x5678)!
				#expect(future.broadcastResultValue(resType: 3, resVal: data) == true)
			}
			// wait asynchronously for the future to complete
			let result = try await future.waitAsync()
			
			var foundType:UInt8? = nil
			var foundValue:UnsafeMutableRawPointer? = nil

			// check that the result was received
			switch result {
			case .success(let type, let value):
				foundType = type
				foundValue = value
			default:
				break
			}

			#expect(foundType == 3)
			#expect(foundValue == UnsafeMutableRawPointer(bitPattern: 0x5678))
		}
	}

	// test async waiters cancelling their own tasks
	@Test("__cswiftslash_future :: core :: async waiter invalidation")
	func coreAsyncWaiterInvalidation() async throws {
		let future = Harness()
		try await withThrowingTaskGroup(of:FutureTests.Harness.Result?.self) { tg in
			tg.addTask {
				return try await future.waitAsync()
			}
			tg.cancelAll()
			var i = 0
			for try await result in tg {
				#expect(result == nil)
				i += 1
			}
			#expect(i == 1)
		}
	}

	// test async waiters receiving errors
	@Test("__cswiftslash_future :: core :: async error")
	func coreAsyncError() async throws {
		try await withThrowingTaskGroup(of:Void.self, returning:Void.self) { tg in
			let future = Harness()
			tg.addTask {
				let errorData = UnsafeMutableRawPointer(bitPattern: 0xbeef)!
				#expect(future.broadcastErrorValue(errType: 4, errVal: errorData) == true)
			}
			// wait asynchronously for the future to complete
			let result = try await future.waitAsync()
			
			var foundType:UInt8? = nil
			var foundValue:UnsafeMutableRawPointer? = nil

			// check that the error was received
			switch result {
			case .failure(let type, let value):
				foundType = type
				foundValue = value
			default:
				break
			}

			#expect(foundType == 4)
			#expect(foundValue == UnsafeMutableRawPointer(bitPattern: 0xbeef))
		}
	}

	@Test("__cswiftslash_future :: core :: async cancel")
	func coreAsyncCancel() async throws {
		let future = Harness()
		try await withThrowingTaskGroup(of:Void.self) { tg in
			tg.addTask {
				#expect(future.cancel() == true)
			}
			let waitResult = try await future.waitAsync()
			#expect(waitResult == nil)
		}
	}

	// MARK: - Additional Tests
	@Test("__cswiftslash_future :: broadcast result multiple times")
	func testBroadcastResultMultipleTimes() async throws {
		try await withThrowingTaskGroup(of:Void.self) { tg in
			let future = Harness()
			tg.addTask {
				let data1 = UnsafeMutableRawPointer(bitPattern: 0x1000)!
				#expect(future.broadcastResultValue(resType: 1, resVal: data1) == true)
				
				// attempt to broadcast again
				let data2 = UnsafeMutableRawPointer(bitPattern: 0x2000)!
				#expect(future.broadcastResultValue(resType: 2, resVal: data2) == false)
			}
			// wait synchronously for the future to complete
			let result = try future.waitSync()
			
			var foundType:UInt8? = nil
			var foundValue:UnsafeMutableRawPointer? = nil

			// check that only the first result was received
			switch result {
			case .success(let type, let value):
				foundType = type
				foundValue = value
			default:
				break
			}

			#expect(foundType == 1)
			#expect(foundValue == UnsafeMutableRawPointer(bitPattern: 0x1000))
		}
	}

	@Test("__cswiftslash_future :: broadcast error after result")
	func testBroadcastErrorAfterResult() async throws {
		try await withThrowingTaskGroup(of:Void.self) { tg in
			let future = Harness()
			tg.addTask {
				let data = UnsafeMutableRawPointer(bitPattern: 0x3000)!
				#expect(future.broadcastResultValue(resType: 5, resVal: data) == true)
				
				// attempt to broadcast an error after the result
				let errorData = UnsafeMutableRawPointer(bitPattern: 0x4000)!
				#expect(future.broadcastErrorValue(errType: 6, errVal: errorData) == false)
			}
			// wait synchronously for the future to complete
			let result = try future.waitSync()
			
			var foundType:UInt8? = nil
			var foundValue:UnsafeMutableRawPointer? = nil

			// check that the result was received and error was not
			switch result {
			case .success(let type, let value):
				foundType = type
				foundValue = value
			default:
				break
			}

			#expect(foundType == 5)
			#expect(foundValue == UnsafeMutableRawPointer(bitPattern: 0x3000))
		}
	}

	@Test("__cswiftslash_future :: broadcast error multiple times")
	func testBroadcastErrorAfterError() async throws {
		try await withThrowingTaskGroup(of:Void.self) { tg in
			let future = Harness()
			tg.addTask {
				let errorData1 = UnsafeMutableRawPointer(bitPattern: 0x5000)!
				#expect(future.broadcastErrorValue(errType: 7, errVal: errorData1) == true)
				
				// attempt to broadcast another error
				let errorData2 = UnsafeMutableRawPointer(bitPattern: 0x6000)!
				#expect(future.broadcastErrorValue(errType: 8, errVal: errorData2) == false)
			}
			// wait synchronously for the future to complete
			let result = try future.waitSync()
			
			var foundType:UInt8? = nil
			var foundValue:UnsafeMutableRawPointer? = nil

			// check that only the first error was received
			switch result {
			case .failure(let type, let value):
				foundType = type
				foundValue = value
			default:
				break
			}

			#expect(foundType == 7)
			#expect(foundValue == UnsafeMutableRawPointer(bitPattern: 0x5000))
		}
	}

	@Test("__cswiftslash_future :: broadcast result after error")
	func testBroadcastResultAfterError() async throws {
		try await withThrowingTaskGroup(of:Void.self) { tg in
			let future = Harness()
			tg.addTask {
				let errorData = UnsafeMutableRawPointer(bitPattern: 0x7000)!
				#expect(future.broadcastErrorValue(errType: 9, errVal: errorData) == true)
				
				// attempt to broadcast a result after the error
				let data = UnsafeMutableRawPointer(bitPattern: 0x8000)!
				#expect(future.broadcastResultValue(resType: 10, resVal: data) == false)
			}
			// wait synchronously for the future to complete
			let result = try future.waitSync()
			
			var foundType:UInt8? = nil
			var foundValue:UnsafeMutableRawPointer? = nil

			// check that the error was received and result was not
			switch result {
			case .failure(let type, let value):
				foundType = type
				foundValue = value
			default:
				break
			}

			#expect(foundType == 9)
			#expect(foundValue == UnsafeMutableRawPointer(bitPattern: 0x7000))
		}
	}

	@Test("__cswiftslash_future :: fuzz testing")
	func testFuzzTestingFuture() async throws {
		for _ in 0..<100000 {
			await withTaskGroup(of:UInt8?.self) { tgg in
				let future = Harness()
				let action = Int.random(in: 0...22)
				tgg.addTask {
					if action <= 10 {
						// broadcast result
						let data = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
						let randomByte = UInt8.random(in: 0...255)
						data.storeBytes(of:randomByte, as: UInt8.self)
						#expect(future.broadcastResultValue(resType: 11, resVal: data) == true)
						return randomByte
					} else if action <= 20 {
						// broadcast error
						let errorData = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
						let randomByte = UInt8.random(in: 0...255)
						errorData.storeBytes(of:randomByte, as: UInt8.self)
						#expect(future.broadcastErrorValue(errType: 12, errVal: errorData) == true)
						return randomByte
					} else {
						// cancel the future
						#expect(future.cancel() == true)
						return nil
					}
				}
				let result = await withUnsafeContinuation({ (cont:UnsafeContinuation<FutureTests.Harness.Result?, Never>) in 
					do {
						cont.resume(returning:try future.waitSync())
					} catch let error {
						fatalError("\(error)")
					}
				})
				switch result {
					case .success(let valType, let valPtr):
						#expect(action <= 10)
						#expect(valType == 11)
						let foundByte = valPtr!.load(as: UInt8.self)
						let expectedByte = await tgg.next()!
						#expect(foundByte == expectedByte)
						valPtr!.deallocate()
					case .failure(let valType, let valPtr):
						#expect(action > 10 && action <= 20)
						#expect(valType == 12)
						let foundByte = valPtr!.load(as: UInt8.self)
						let expectedByte = await tgg.next()!
						#expect(foundByte == expectedByte)
						valPtr!.deallocate()
					case .none:
						#expect(action > 20)
						let expectedByte = await tgg.next()!
						#expect(expectedByte == nil)
				}
			}
		}
	}

	// MARK: - Additional Test Cases for Multiple Waiters
	@Test("__cswiftslash_future :: multiple waiters :: async result")
	func testMultipleWaitersAsyncResult() async throws {
		let future = Harness()
		let waiterCount = 5
		var results = [Harness.Result?](repeating: nil, count: waiterCount)
		
		// start multiple async waiters
		try await withThrowingTaskGroup(of: (Int, Harness.Result?).self) { group in
			for i in 0..<waiterCount {
				group.addTask {
					do {
						let result = try await future.waitAsync()
						return (i, result)
					} catch {
						return (i, nil)
					}
				}
			}
			
			// broadcast a result after some delay
			let data = UnsafeMutableRawPointer(bitPattern: 0x9999)!
			#expect(future.broadcastResultValue(resType: 42, resVal: data) == true)
			
			// collect results from waiters
			for _ in 0..<waiterCount {
				let (index, result) = try await group.next()!
				results[index] = result
			}
		}
		
		// Verify that all waiters received the result
		for result in results {
			#expect(result == .success(42, UnsafeMutableRawPointer(bitPattern: 0x9999)))
		}
	}

	@Test("__cswiftslash_future :: multiple waiters :: async error")
	func testMultipleWaitersAsyncError() async throws {
		let future = Harness()
		let waiterCount = 5
		var results = [Harness.Result?](repeating: nil, count: waiterCount)
		
		// start multiple async waiters
		try await withThrowingTaskGroup(of: (Int, Harness.Result?).self) { group in
			for i in 0..<waiterCount {
				group.addTask {
					do {
						let result = try await future.waitAsync()
						return (i, result)
					} catch {
						return (i, nil)
					}
				}
			}
			
			// broadcast an error after some delay
			let errorData = UnsafeMutableRawPointer(bitPattern: 0xAAAA)!
			#expect(future.broadcastErrorValue(errType: 24, errVal: errorData) == true)
			
			// collect results from waiters
			for _ in 0..<waiterCount {
				let (index, result) = try await group.next()!
				results[index] = result
			}
		}
		
		// verify that all waiters received the error
		for result in results {
			var foundType: UInt8? = nil
			var foundValue: UnsafeMutableRawPointer? = nil
			switch result {
			case .failure(let type, let value):
				foundType = type
				foundValue = value
			default:
				break;
			}
			#expect(foundType == 24)
			#expect(foundValue == UnsafeMutableRawPointer(bitPattern: 0xAAAA))
		}
	}

	@Test("__cswiftslash_future :: multiple waiters :: broadcast before wait")
	func testBroadcastBeforeWaiters() async throws {
		let future = Harness()
		
		// broadcast a result immediately
		let data = UnsafeMutableRawPointer(bitPattern: 0xCCCC)!
		#expect(future.broadcastResultValue(resType: 99, resVal: data) == true)
		
		let waiterCount = 4
		var results = [Harness.Result?](repeating: nil, count: waiterCount)
		
		// start multiple waiters after the result has been broadcasted
		await withTaskGroup(of: (Int, Harness.Result?).self) { group in
			for i in 0..<waiterCount {
				group.addTask {
					do {
						let result = try await future.waitAsync()
						return (i, result)
					} catch {
						return (i, nil)
					}
				}
			}
			
			// collect results from waiters
			for _ in 0..<waiterCount {
				let (index, result) = await group.next()!
				results[index] = result
			}
		}
		
		// verify that all waiters immediately received the result
		for result in results {
			var foundType: UInt8? = nil
			var foundValue: UnsafeMutableRawPointer? = nil
			switch result {
			case .success(let type, let value):
				foundType = type
				foundValue = value
			default:
				break;
			}
			#expect(foundType == 99)
			#expect(foundValue == UnsafeMutableRawPointer(bitPattern:0xCCCC))
		}
	}

	@Test("__cswiftslash_future :: multiple waiters :: error and result race")
	func testMultipleWaitersErrorAndResultRace() async throws {
		let future = Harness()
		let waiterCount = 6
		var results = [Harness.Result?](repeating: nil, count: waiterCount)
		
		// start multiple waiters
		await withTaskGroup(of: (Int, Harness.Result?).self) { group in
			for i in 0..<waiterCount {
				group.addTask {
					do {
						let result = try await future.waitAsync()
						return (i, result)
					} catch {
						return (i, nil)
					}
				}
			}
			
			// simultaneously attempt to broadcast result and error
			await withTaskGroup(of:Bool.self) { broadcastGroup in
				broadcastGroup.addTask {
					let data = UnsafeMutableRawPointer(bitPattern: 0xDDDD)!
					return future.broadcastResultValue(resType: 77, resVal: data)
				}
				broadcastGroup.addTask {
					let errorData = UnsafeMutableRawPointer(bitPattern: 0xEEEE)!
					return future.broadcastErrorValue(errType: 88, errVal: errorData)
				}

				var foundTrue = false
				var foundFalse = false
				var i = 0
				for await result in broadcastGroup {
					if result == false {
						#expect(foundFalse == false)
						foundFalse = true
					} else {
						#expect(foundTrue == false)
						foundTrue = true
					}
					i += 1
				}
				#expect(i == 2)
				#expect(foundTrue == true)
				#expect(foundFalse == true)
			}
			
			// collect results from waiters
			for await (index, result) in group {
				results[index] = result
			}
		}
		
		// verify that all waiters received either the result or the error
		var resultCount = 0
		var errorCount = 0
		for result in results {
			#expect(result == .success(77, UnsafeMutableRawPointer(bitPattern: 0xDDDD)) || result == .failure(88, UnsafeMutableRawPointer(bitPattern: 0xEEEE)))
			if case .success = result {
				resultCount += 1
			} else {
				errorCount += 1
			}
		}
		
		// ensure that either the result or the error was broadcasted
		#expect((resultCount == waiterCount && errorCount == 0) || (resultCount == 0 && errorCount == waiterCount))
	}
}