/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Testing
@testable import __cswiftslash_future

import Synchronization

extension Tag {
	@Tag internal static var __cswiftslash_future:Self
}

extension __cswiftslash_tests {
	@Suite("__cswiftslash_future",
		.serialized,
		.tags(.__cswiftslash_future)
	)
	internal struct __cswiftslash_future {
		// MARK: c harness
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

			fileprivate func hasResult() -> Bool {
				return __cswiftslash_future_t_has_result(futurePtr)
			}

			fileprivate func cancel() -> Bool {
				__cswiftslash_future_t_broadcast_cancel(futurePtr)
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
					__cswiftslash_future_t_wait_async_invalidate(futurePtr, keyThing)
				})
				return resultStore!.1
			}
			internal func broadcastResultValue(resType: UInt8, resVal:UnsafeMutableRawPointer?) -> Bool {
				return __cswiftslash_future_t_broadcast_res_val(futurePtr, resType, resVal)
			}
			internal func broadcastErrorValue(errType: UInt8, errVal:UnsafeMutableRawPointer?) -> Bool {
				return __cswiftslash_future_t_broadcast_res_throw(futurePtr, errType, errVal)
			}

			fileprivate struct UnexpectedAsyncronousThreading:Swift.Error {}
			private final class AsyncResult {

				private var expectedPID:pthread_t? = nil
				
				private var istate = pthread_mutex_t()

				private var mutex:pthread_mutex_t = pthread_mutex_t()
				private let isMutexLocked:UnsafeMutablePointer<Atomic<Bool>>
				
				private var resultHandler:Optional<(UInt8, UnsafeMutableRawPointer?) -> Void>
				private var errorHandler:Optional<(UInt8, UnsafeMutableRawPointer?) -> Void>
				private var cancelHandler:Optional<() -> Void>

				fileprivate init(resultHandler rh:@escaping((UInt8, UnsafeMutableRawPointer?) -> Void), errorHandler eh:@escaping((UInt8, UnsafeMutableRawPointer?) -> Void), cancelHandler ch:@escaping(() -> Void)) {
					resultHandler = rh
					errorHandler = eh
					cancelHandler = ch
					isMutexLocked = UnsafeMutablePointer<Atomic<Bool>>.allocate(capacity:1)
					isMutexLocked.initialize(to:Atomic<Bool>(false))
					pthread_mutex_init(&mutex, nil)
					pthread_mutex_lock(&mutex)
					pthread_mutex_init(&istate, nil)
				}

				fileprivate func setResult(type:UInt8, pointer result:__cswiftslash_optr_t?) {
					pthread_mutex_lock(&istate)
					resultHandler?(type, result)
					if isMutexLocked.pointee.compareExchange(expected: false, desired: true, successOrdering: .acquiring, failureOrdering: .relaxed).exchanged == true {
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
					if isMutexLocked.pointee.compareExchange(expected: false, desired: true, successOrdering: .acquiring, failureOrdering: .relaxed).exchanged == true {
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
					if isMutexLocked.pointee.compareExchange(expected: false, desired: true, successOrdering: .acquiring, failureOrdering: .relaxed).exchanged == true {
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
						isMutexLocked.pointee.store(false, ordering:.releasing)
					}
					let ret = expectedPID!
					pthread_mutex_unlock(&istate)
					return ret
				}

				deinit {
					pthread_mutex_lock(&istate)
					if isMutexLocked.pointee.load(ordering:.acquiring) == true {
						pthread_mutex_unlock(&mutex)
					}
					pthread_mutex_unlock(&istate)
					pthread_mutex_destroy(&mutex)
					isMutexLocked.deinitialize(count:1)
					isMutexLocked.deallocate()
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
			internal func waitSync() async throws -> Result? {
				try await withUnsafeThrowingContinuation { (cont:UnsafeContinuation<Result?, Swift.Error>) in
					do {
						let mytid = pthread_self()
						var srInstance = SyncResult()
						withUnsafeMutablePointer(to:&srInstance) { srInstance in
							var memory = __cswiftslash_future_wait_t_init_struct()
							let ptr = __cswiftslash_future_t_wait_sync_register(futurePtr, srInstance, Self.futureSyncResultHandler, Self.futureSyncErrorHandler, Self.futureSyncCancelHandler, &memory)
							guard ptr != nil else {
								return
							}
							__cswiftslash_future_t_wait_sync_block(futurePtr, ptr!)
						}
						let getr = try srInstance.getResult()
						guard pthread_equal(mytid, getr.1) != 0 else {
							cont.resume(throwing:UnexpectedSyncronousThreading())
							return
						}
						cont.resume(returning:getr.0)
					} catch let error {
						cont.resume(throwing:error)
					}
				}
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

		// MARK: - core sync tests
		@Suite("__cswiftslash_future core (sync)",
			.serialized
		)
		struct CoreSync {
			private var future = Harness()

			@Test("__cswiftslash_future :: core :: sync result", .timeLimit(.minutes(1)))
			func testWaitSyncForResult() async throws {
				try await withThrowingTaskGroup(of:Void.self, returning:Void.self) { tg in
					#expect(future.hasResult() == false)
					tg.addTask {
						let data = UnsafeMutableRawPointer(bitPattern: 0x1234)!
						#expect(future.hasResult() == false)
						#expect(future.broadcastResultValue(resType: 1, resVal: data) == true)
						#expect(future.hasResult() == true)
					}
					// wait synchronously for the future to complete
					let result = try await future.waitSync()
					#expect(future.hasResult() == true)

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

			@Test("__cswiftslash_future :: core :: sync error", .timeLimit(.minutes(1)))
			func testWaitSyncForError() async throws {
				try await withThrowingTaskGroup(of:Void.self, returning:Void.self) { tg in
					#expect(future.hasResult() == false)
					tg.addTask {
						let errorData = UnsafeMutableRawPointer(bitPattern: 0x4321)!
						#expect(future.hasResult() == false)
						#expect(future.broadcastErrorValue(errType: 2, errVal: errorData) == true)
						#expect(future.hasResult() == true)
					}

					// wait synchronously for the future to complete
					let result = try await future.waitSync()
					#expect(future.hasResult() == true)
					
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

			@Test("__cswiftslash_future :: core :: sync cancel", .timeLimit(.minutes(1)))
			func testSyncWaiterCancellation() async throws {
				try await withThrowingTaskGroup(of:__cswiftslash_future.Harness.Result?.self) { tg in
					#expect(future.hasResult() == false)
					tg.addTask {
						defer {
							#expect(future.hasResult() == true)
						}
						return try await future.waitSync()
					}
					#expect(future.cancel() == true)
					#expect(future.hasResult() == true)
					var i = 0
					for try await result in tg {
						#expect(result == nil)
						i += 1
					}
					#expect(i == 1)
				}
			}
		}

		// MARK: - core async tests
		@Suite("__cswiftslash_future core (async)",
			.serialized
		)
		struct CoreAsync {
			private var future = Harness()

			// test async waiters receiving results
			@Test("__cswiftslash_future :: core :: async result", .timeLimit(.minutes(1)))
			func testWaitAsyncForResult() async throws {
				try await withThrowingTaskGroup(of:Void.self, returning:Void.self) { tg in
					tg.addTask {
						let data = UnsafeMutableRawPointer(bitPattern: 0x5678)!
						#expect(future.hasResult() == false)
						#expect(future.broadcastResultValue(resType: 3, resVal: data) == true)
						#expect(future.hasResult() == true)
					}
					// wait asynchronously for the future to complete
					#expect(future.hasResult() == false)
					let result = try await future.waitAsync()
					#expect(future.hasResult() == true)
					
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
			@Test("__cswiftslash_future :: core :: async waiter invalidation", .timeLimit(.minutes(1)))
			func coreAsyncWaiterInvalidation() async throws {
				try await withThrowingTaskGroup(of:__cswiftslash_future.Harness.Result?.self) { tg in
					tg.addTask {
						#expect(future.hasResult() == false)
						defer {
							// cancelling a single waiter is not the same as cancelling the future. since the waiters here will cancel but the result will not be set, we still expect false for result.
							#expect(future.hasResult() == false)
						}
						let asr = try await future.waitAsync()
						return asr
					}
					tg.cancelAll()
					var i = 0
					#expect(future.hasResult() == false)
					for try await result in tg {
						#expect(result == nil)
						i += 1
					}
					#expect(i == 1)
				}
			}

			// test async waiters receiving errors
			@Test("__cswiftslash_future :: core :: async error", .timeLimit(.minutes(1)))
			func coreAsyncError() async throws {
				try await withThrowingTaskGroup(of:Void.self, returning:Void.self) { tg in
					tg.addTask {
						let errorData = UnsafeMutableRawPointer(bitPattern: 0xbeef)!
						#expect(future.hasResult() == false)
						#expect(future.broadcastErrorValue(errType: 4, errVal: errorData) == true)
						#expect(future.hasResult() == true)
					}
					// wait asynchronously for the future to complete
					#expect(future.hasResult() == false)
					let result = try await future.waitAsync()
					#expect(future.hasResult() == true)
					
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

			@Test("__cswiftslash_future :: core :: async cancel", .timeLimit(.minutes(1)))
			func coreAsyncCancel() async throws {
				try await withThrowingTaskGroup(of:Void.self) { tg in
					tg.addTask {
						try await Task.sleep(nanoseconds:100_000)
						#expect(future.hasResult() == false)
						#expect(future.cancel() == true)
						#expect(future.hasResult() == true)
					}
					#expect(future.hasResult() == false)
					let waitResult = try await future.waitAsync()
					#expect(future.hasResult() == true)
					#expect(waitResult == nil)
				}
			}
		}

		// MARK: - additional tests
		@Suite("__cswiftslash_future (additional coverage)",
			.serialized
		)
		struct Additional {
			private var future = Harness()

			@Test("__cswiftslash_future :: broadcast result multiple times", .timeLimit(.minutes(1)))
			func testBroadcastResultMultipleTimes() async throws {
				try await withThrowingTaskGroup(of:Void.self) { tg in
					#expect(future.hasResult() == false)
					tg.addTask {
						let data1 = UnsafeMutableRawPointer(bitPattern: 0x1000)!
						#expect(future.hasResult() == false)
						#expect(future.broadcastResultValue(resType: 1, resVal: data1) == true)
						#expect(future.hasResult() == true)
						
						// attempt to broadcast again
						let data2 = UnsafeMutableRawPointer(bitPattern: 0x2000)!
						#expect(future.hasResult() == true)
						#expect(future.broadcastResultValue(resType: 2, resVal: data2) == false)
						#expect(future.hasResult() == true)
					}
					// wait synchronously for the future to complete
					let result = try await future.waitSync()
					#expect(future.hasResult() == true)
					
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

			@Test("__cswiftslash_future :: broadcast error after result", .timeLimit(.minutes(1)))
			func testBroadcastErrorAfterResult() async throws {
				try await withThrowingTaskGroup(of:Void.self) { tg in
					#expect(future.hasResult() == false)
					tg.addTask {
						let data = UnsafeMutableRawPointer(bitPattern: 0x3000)!
						#expect(future.hasResult() == false)
						#expect(future.broadcastResultValue(resType: 5, resVal: data) == true)
						#expect(future.hasResult() == true)

						// attempt to broadcast an error after the result
						let errorData = UnsafeMutableRawPointer(bitPattern: 0x4000)!
						#expect(future.hasResult() == true)
						#expect(future.broadcastErrorValue(errType: 6, errVal: errorData) == false)
						#expect(future.hasResult() == true)
					}
					// wait synchronously for the future to complete
					let result = try await future.waitSync()
					#expect(future.hasResult() == true)
					
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

			@Test("__cswiftslash_future :: broadcast error multiple times", .timeLimit(.minutes(1)))
			func testBroadcastErrorAfterError() async throws {
				try await withThrowingTaskGroup(of:Void.self) { tg in
					#expect(future.hasResult() == false)
					tg.addTask {
						let errorData1 = UnsafeMutableRawPointer(bitPattern: 0x5000)!
						#expect(future.hasResult() == false)
						#expect(future.broadcastErrorValue(errType: 7, errVal: errorData1) == true)
						#expect(future.hasResult() == true)
						
						// attempt to broadcast another error
						let errorData2 = UnsafeMutableRawPointer(bitPattern: 0x6000)!
						#expect(future.hasResult() == true)
						#expect(future.broadcastErrorValue(errType: 8, errVal: errorData2) == false)
						#expect(future.hasResult() == true)
					}
					// wait synchronously for the future to complete
					let result = try await future.waitSync()
					#expect(future.hasResult() == true)
					
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

			@Test("__cswiftslash_future :: broadcast result after error", .timeLimit(.minutes(1)))
			func testBroadcastResultAfterError() async throws {
				try await withThrowingTaskGroup(of:Void.self) { tg in
					#expect(future.hasResult() == false)
					tg.addTask {
						let errorData = UnsafeMutableRawPointer(bitPattern: 0x7000)!
						#expect(future.hasResult() == false)
						#expect(future.broadcastErrorValue(errType: 9, errVal: errorData) == true)
						#expect(future.hasResult() == true)
						
						// attempt to broadcast a result after the error
						let data = UnsafeMutableRawPointer(bitPattern: 0x8000)!
						#expect(future.hasResult() == true)
						#expect(future.broadcastResultValue(resType: 10, resVal: data) == false)
						#expect(future.hasResult() == true)
					}
					// wait synchronously for the future to complete
					let result = try await future.waitSync()
					#expect(future.hasResult() == true)
					
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

			@Test("__cswiftslash_future :: fuzz testing", .timeLimit(.minutes(1)))
			mutating func testFuzzTestingFuture() async throws {
				for _ in 0..<100000 {
					await withTaskGroup(of:UInt8?.self) { [future] tgg in
						let action = Int.random(in: 0...22)
						#expect(future.hasResult() == false)
						tgg.addTask {
							if action <= 10 {
								// broadcast result
								let data = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
								let randomByte = UInt8.random(in: 0...255)
								data.storeBytes(of:randomByte, as: UInt8.self)
								#expect(future.hasResult() == false)
								#expect(future.broadcastResultValue(resType: 11, resVal: data) == true)
								#expect(future.hasResult() == true)
								return randomByte
							} else if action <= 20 {
								// broadcast error
								let errorData = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
								let randomByte = UInt8.random(in: 0...255)
								errorData.storeBytes(of:randomByte, as: UInt8.self)
								#expect(future.hasResult() == false)
								#expect(future.broadcastErrorValue(errType: 12, errVal: errorData) == true)
								#expect(future.hasResult() == true)
								return randomByte
							} else {
								// cancel the future
								#expect(future.hasResult() == false)
								#expect(future.cancel() == true)
								#expect(future.hasResult() == true)
								return nil
							}
						}
						let result = try! await future.waitSync()
						#expect(future.hasResult() == true)
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
						await tgg.waitForAll()
					}
					future = Harness()
				}
			}
		}

		// MARK: - additional tests for multiple waiters
		@Suite("__cswiftslash_future (multiple waiters)",
			.serialized
		)
		struct MultipleWaiters {
			@Test("__cswiftslash_future :: multiple waiters :: async result", .timeLimit(.minutes(1)))
			func testMultipleWaitersAsyncResult() async throws {
				let future = Harness()
				let waiterCount = 5
				var results = [Harness.Result?](repeating: nil, count: waiterCount)
				
				// start multiple async waiters
				try await withThrowingTaskGroup(of: (Int, Harness.Result?).self) { group in
					for i in 0..<waiterCount {
						#expect(future.hasResult() == false)
						group.addTask {
							do {
								let result = try await future.waitAsync()
								#expect(future.hasResult() == true)
								return (i, result)
							} catch {
								return (i, nil)
							}
						}
					}
					
					// broadcast a result
					let data = UnsafeMutableRawPointer(bitPattern: 0x9999)!
					#expect(future.hasResult() == false)
					#expect(future.broadcastResultValue(resType: 42, resVal: data) == true)
					#expect(future.hasResult() == true)
					
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

			@Test("__cswiftslash_future :: multiple waiters :: async error", .timeLimit(.minutes(1)))
			func testMultipleWaitersAsyncError() async throws {
				let future = Harness()
				let waiterCount = 5
				var results = [Harness.Result?](repeating: nil, count: waiterCount)
				
				// start multiple async waiters
				try await withThrowingTaskGroup(of: (Int, Harness.Result?).self) { group in
					for i in 0..<waiterCount {
						group.addTask {
							do {
								#expect(future.hasResult() == false)
								let result = try await future.waitAsync()
								#expect(future.hasResult() == true)
								return (i, result)
							} catch {
								return (i, nil)
							}
						}
					}

					try await Task.sleep(nanoseconds: 100_000)
					
					// broadcast an error after some delay
					let errorData = UnsafeMutableRawPointer(bitPattern: 0xAAAA)!
					#expect(future.hasResult() == false)
					#expect(future.broadcastErrorValue(errType: 24, errVal: errorData) == true)
					#expect(future.hasResult() == true)
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

			@Test("__cswiftslash_future :: multiple waiters :: broadcast before wait", .timeLimit(.minutes(1)))
			func testBroadcastBeforeWaiters() async throws {
				let future = Harness()
				
				// broadcast a result immediately
				let data = UnsafeMutableRawPointer(bitPattern: 0xCCCC)!
				#expect(future.hasResult() == false)
				#expect(future.broadcastResultValue(resType: 99, resVal: data) == true)
				#expect(future.hasResult() == true)

				let waiterCount = 4
				var results = [Harness.Result?](repeating: nil, count: waiterCount)
				
				// start multiple waiters after the result has been broadcasted
				await withTaskGroup(of: (Int, Harness.Result?).self) { group in
					for i in 0..<waiterCount {
						group.addTask {
							do {
								#expect(future.hasResult() == true)
								let result = try await future.waitAsync()
								#expect(future.hasResult() == true)
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

			@Test("__cswiftslash_future :: multiple waiters :: error and result race", .timeLimit(.minutes(1)))
			func testMultipleWaitersErrorAndResultRace() async throws {
				let future = Harness()
				let waiterCount = 6
				var results = [Harness.Result?](repeating: nil, count: waiterCount)
				
				// start multiple waiters
				await withTaskGroup(of: (Int, Harness.Result?).self) { group in
					for i in 0..<waiterCount {
						#expect(future.hasResult() == false)
						group.addTask {
							do {
								let result = try await future.waitAsync()
								#expect(future.hasResult() == true)
								return (i, result)
							} catch {
								return (i, nil)
							}
						}
					}
					
					// simultaneously attempt to broadcast result and error
					await withTaskGroup(of:Bool.self) { broadcastGroup in
						#expect(future.hasResult() == false)
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
						#expect(future.hasResult() == true)
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
	}
}