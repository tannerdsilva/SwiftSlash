/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Testing

@testable import __cswiftslash_threads

import func Foundation.sleep
import func Foundation.usleep
import func Foundation.getpid

extension Tag {
	@Tag internal static var __cswiftslash_threads:Self
}

extension __cswiftslash_tests {
	@Suite("__cswiftslash_threads",
		.serialized,
		.tags(.__cswiftslash_threads)
	)
	internal struct ThreadTests {
		// MARK: mutex tool
		fileprivate final class Mutex {
			private var mutex = pthread_mutex_t()
			fileprivate init() {
				pthread_mutex_init(&mutex, nil)
			}
			fileprivate func lock() {
				pthread_mutex_lock(&mutex)
			}
			fileprivate func unlock() {
				pthread_mutex_unlock(&mutex)
			}
			deinit {
				pthread_mutex_destroy(&mutex)
			}
		}

		// MARK: c harness
		fileprivate final class ThreadHarness:@unchecked Sendable {
			// keeps track of which handlers were called and in what order
			fileprivate enum HandlerCall: Equatable {
				case allocatorCalled
				case mainCalled(pthread_t)
				case cancelCalled
				case deallocCalled
			}
		
			fileprivate let handlerCalls:UnsafeMutablePointer<Array<HandlerCall>> = .allocate(capacity:1)
			fileprivate let handlerCallsLock = Mutex()
		
			// thread
			fileprivate var thread:__cswiftslash_threads_t_type? = nil
		
			// function pointers for the thread configuration
			fileprivate let alloc_f:__cswiftslash_threads_alloc_f!
			fileprivate let run_f:UnsafeMutablePointer<__cswiftslash_threads_main_f> = .allocate(capacity:1)
			fileprivate let cancel_f:__cswiftslash_threads_cancel_f!
			fileprivate let dealloc_f:__cswiftslash_threads_dealloc_f!
		
			fileprivate init() {
				handlerCalls.initialize(to: [])

				// define the function pointers
				alloc_f = { arg in
					let harness = Unmanaged<ThreadHarness>.fromOpaque(arg).takeUnretainedValue()
					harness.handlerCallsLock.lock()
					harness.handlerCalls.pointee.append(.allocatorCalled)
					harness.handlerCallsLock.unlock()
					return Unmanaged.passUnretained(harness).toOpaque()
				}
			
				run_f.initialize(to:{ ws in
					let harness = Unmanaged<ThreadHarness>.fromOpaque(ws).takeUnretainedValue()
					harness.handlerCallsLock.lock()
					harness.handlerCalls.pointee.append(.mainCalled(pthread_self()))
					harness.handlerCallsLock.unlock()
					sleep(1) // sleep for 1 second to simulate work
				})
			
				cancel_f = { ws in
					let harness = Unmanaged<ThreadHarness>.fromOpaque(ws).takeUnretainedValue()
					harness.handlerCallsLock.lock()
					harness.handlerCalls.pointee.append(.cancelCalled)
					harness.handlerCallsLock.unlock()
				}
			
				dealloc_f = { ws in
					let harness = Unmanaged<ThreadHarness>.fromOpaque(ws).takeUnretainedValue()
					harness.handlerCallsLock.lock()
					harness.handlerCalls.pointee.append(.deallocCalled)
					harness.handlerCallsLock.unlock()
				}
			}
		
			fileprivate func startThread() {
				let arg = Unmanaged.passUnretained(self).toOpaque()
				let config = __cswiftslash_threads_config_init(
					arg,
					alloc_f,
					run_f.pointee,
					cancel_f,
					dealloc_f
				)
				var result:Int32 = 0
				let thread = __cswiftslash_threads_config_run(config, &result)
				self.thread = thread
			}
		
			fileprivate func cancelThread() {
				pthread_cancel(thread!)
			}
		
			fileprivate func joinThread() async -> [HandlerCall] {
				await withUnsafeContinuation { (continuation:UnsafeContinuation<Void, Never>) in
					pthread_join(thread!, nil)
					continuation.resume()
				}
				return await withUnsafeContinuation { (continuation:UnsafeContinuation<[HandlerCall], Never>) in
					handlerCallsLock.lock()
					continuation.resume(returning:handlerCalls.pointee)
					handlerCallsLock.unlock()
				}
			}

			deinit {
				handlerCalls.deinitialize(count:1)
				handlerCalls.deallocate()
				run_f.deinitialize(count:1)
				run_f.deallocate()
			}
		}

		// MARK: test cases
		@Test("__cswiftslash_threads :: sequence (no cancellation)", .timeLimit(.minutes(1)))
		func testThreadCompletionHandlers() async {
			let harness = ThreadHarness()
			harness.startThread()
		
			// wait for thread to complete
			let calls = await harness.joinThread()
				
			#expect(calls.count == 3, "expected 3 handler calls, got \(calls.count)")
			#expect(calls[0] == .allocatorCalled, "expected allocator to be called first")
			#expect(calls[1] == .mainCalled(harness.thread!), "expected main function to be called second")
			#expect(calls[2] == .deallocCalled, "expected deallocator to be called last")
		}

		@Test("__cswiftslash_threads :: sequence (immediate cancellation)", .timeLimit(.minutes(1)))
		func testThreadCancellationHandlers() async {
			let harness = ThreadHarness()
			harness.startThread()
		
			// cancel the thread
			harness.cancelThread()
		
			// wait for thread to complete
			let calls = await harness.joinThread()

			#expect(calls.count == 4 || calls.count == 3, "expected 3 or 4 handler calls, got \(calls.count)")
			switch harness.handlerCalls.pointee.count {
			case 4:
				#expect(calls[0] == .allocatorCalled, "expected allocator to be called first")
				#expect(calls[1] == .mainCalled(harness.thread!), "expected main function to be called second")
				#expect(calls[2] == .cancelCalled, "expected cancel handler to be called third")
				#expect(calls[3] == .deallocCalled, "expected deallocator to be called last")
			case 3:
				#expect(calls[0] == .allocatorCalled, "expected allocator to be called first")
				#expect(calls[1] == .cancelCalled, "expected cancel handler to be called second")
				#expect(calls[2] == .deallocCalled, "expected deallocator to be called last")
			default:
				break
			}
		}

		@Test("__cswiftslash_threads :: deallocate short circuit", .timeLimit(.minutes(1)))
		func testDeallocatorAlwaysCalled() async {
			let harness = ThreadHarness()
			harness.startThread()
		
			// cancel the thread immediately
			harness.cancelThread()
		
			// wait for thread to complete
			let calls = await harness.joinThread()
		
			// check that deallocCalled is in the handler calls
			#expect(calls.contains(.deallocCalled), "deallocator was not called")
		}

		@Test("__cswiftslash_threads :: deallocate on immediate exit", .timeLimit(.minutes(1)))
		func testDeallocatorCalledOnImmediateExit() async {
			let harness = ThreadHarness()
		
			// modify main function to exit immediately
			harness.run_f.pointee = { ws in
				// exit immediately
				return
			}
		
			harness.startThread()
			let calls = await harness.joinThread()
		
			// check that deallocCalled is in the handler calls
			#expect(calls.contains(.deallocCalled) == true, "deallocator was not called")
		}

		@Test("__cswiftslash_threads :: cancellation after work completion", .timeLimit(.minutes(1)))
		func testCancellationAfterWorkCompletion() async {
			let harness = ThreadHarness()
		
			harness.startThread()
		
			// ensure main function has time to complete
			usleep(2_000_000) // 2s
			harness.cancelThread()
			let calls = await harness.joinThread()
		
			#expect(calls.count == 3, "expected 3 handler calls, got \(calls.count)")
			#expect(calls[0] == .allocatorCalled, "expected allocator to be called first")
			#expect(calls[1] == .mainCalled(harness.thread!), "expected main function to be called second")
			#expect(calls[2] == .deallocCalled, "expected deallocator to be called last")
			#expect(calls.contains(.cancelCalled) == false, "cancel handler should not be called if work is already completed")
		}

		@Test("__cswiftslash_threads :: concurrent threads with cancellation", .timeLimit(.minutes(1)))
		func testConcurrentThreadsWithCancellation() async {
			let threadCount = 10
			var harnesses: [ThreadHarness] = []
		
			for _ in 0..<threadCount {
				let harness = ThreadHarness()
				harness.startThread()
				harnesses.append(harness)
			}

			usleep(100_000) // 100ms
		
			// cancel half of the threads
			for (index, harness) in harnesses.enumerated() {
				if index % 2 == 0 {
					harness.cancelThread()
				}
			}
		
			// wait for all threads to complete
			for harness in harnesses {
				let calls = await harness.joinThread()
				if calls.contains(.cancelCalled) {
					// thread was cancelled
					switch calls.count {
					case 4:
						#expect(calls[0] == .allocatorCalled, "expected allocator first")
						#expect(calls[1] == .mainCalled(harness.thread!), "expected main function second")
						#expect(calls[2] == .cancelCalled, "expected cancel handler third")
						#expect(calls[3] == .deallocCalled, "expected deallocator last")
					case 3:
						#expect(calls[0] == .allocatorCalled, "expected allocator first")
						#expect(calls[1] == .cancelCalled, "expected cancel handler second")
						#expect(calls[2] == .deallocCalled, "expected deallocator last")
					default:
						#expect(calls.count == 4 || calls.count == 3, "expected 3 or 4 handler calls for cancelled thread")
					}
				} else {
					// thread ran to completion
					#expect(harness.handlerCalls.pointee.count == 3, "expected 3 handler calls for completed thread")
					#expect(harness.handlerCalls.pointee[0] == .allocatorCalled, "expected allocator first")
					#expect(harness.handlerCalls.pointee[1] == .mainCalled(harness.thread!), "expected main function second")
					#expect(harness.handlerCalls.pointee[2] == .deallocCalled, "expected deallocator last")
				}
			}
		}
	}
}