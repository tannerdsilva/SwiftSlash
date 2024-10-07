/*
LICENSE MIT
copyright (c) tanner silva 2024. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Testing

@testable import __cswiftslash_threads

import func Foundation.sleep
import func Foundation.usleep

@Suite("__cswiftslash_threads")
internal struct ThreadTests {
	// MARK: Mutex Tool
	private final class Mutex {
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

	// MARK: C Harness
	private final class ThreadHarness:@unchecked Sendable {
		// Keep track of which handlers were called and in what order
		fileprivate enum HandlerCall: Equatable {
			case allocatorCalled
			case mainCalled
			case cancelCalled
			case deallocCalled
		}
		
		fileprivate var handlerCalls: [HandlerCall] = []
		fileprivate let handlerCallsLock = Mutex()
		
		// Workspace pointer
		fileprivate var workspacePtr:UnsafeMutableRawPointer?
		
		// Thread
		fileprivate var thread:__cswiftslash_threads_t_type?
		
		// Result of pthread_create
		fileprivate var createResult: Int32?
		
		// Function pointers for the thread configuration
		fileprivate var alloc_f:__cswiftslash_threads_alloc_f!
		fileprivate var run_f:__cswiftslash_threads_main_f!
		fileprivate var cancel_f:__cswiftslash_threads_cancel_f!
		fileprivate var dealloc_f:__cswiftslash_threads_dealloc_f!
		
		fileprivate init() {
			// Define the function pointers
			self.alloc_f = { arg in
				let harness = Unmanaged<ThreadHarness>.fromOpaque(arg).takeUnretainedValue()
				harness.handlerCallsLock.lock()
				harness.handlerCalls.append(.allocatorCalled)
				harness.handlerCallsLock.unlock()
				// Allocate workspace (can be any pointer)
				harness.workspacePtr = Unmanaged.passUnretained(harness).toOpaque()
				return harness.workspacePtr!
			}
			
			self.run_f = { ws in
				let harness = Unmanaged<ThreadHarness>.fromOpaque(ws).takeUnretainedValue()
				harness.handlerCallsLock.lock()
				harness.handlerCalls.append(.mainCalled)
				harness.handlerCallsLock.unlock()
				// Simulate work
				sleep(1) // Sleep for 1 second to simulate work
			}
			
			self.cancel_f = { ws in
				let harness = Unmanaged<ThreadHarness>.fromOpaque(ws).takeUnretainedValue()
				harness.handlerCallsLock.lock()
				harness.handlerCalls.append(.cancelCalled)
				harness.handlerCallsLock.unlock()
			}
			
			self.dealloc_f = { ws in
				let harness = Unmanaged<ThreadHarness>.fromOpaque(ws).takeUnretainedValue()
				harness.handlerCallsLock.lock()
				harness.handlerCalls.append(.deallocCalled)
				harness.handlerCallsLock.unlock()
				// Deallocate workspace if needed
				harness.workspacePtr = nil
			}
		}
		
		fileprivate func startThread() {
			// Prepare the config
			let arg = Unmanaged.passUnretained(self).toOpaque()
			let config = __cswiftslash_threads_config_init(
				arg,
				alloc_f,
				run_f,
				cancel_f,
				dealloc_f
			)
			var result: Int32 = 0
			let thread = __cswiftslash_threads_config_run(config, &result)
			self.thread = thread
			self.createResult = result
		}
		
		fileprivate func cancelThread() {
			if let thread = self.thread {
				pthread_cancel(thread)
			}
		}
		
		fileprivate func joinThread() {
			if let thread = self.thread {
				pthread_join(thread, nil)
			}
		}
	}

	@Test("__cswiftslash_threads :: sequence (no cancellation)")
	func testThreadCompletionHandlers() {
		let harness = ThreadHarness()
		harness.startThread()
		
		// Wait for thread to complete
		harness.joinThread()
				
		#expect(harness.handlerCalls.count == 3, "expected 3 handler calls, got \(harness.handlerCalls.count)")
		#expect(harness.handlerCalls[0] == .allocatorCalled, "expected allocator to be called first")
		#expect(harness.handlerCalls[1] == .mainCalled, "expected main function to be called second")
		#expect(harness.handlerCalls[2] == .deallocCalled, "expected deallocator to be called last")
	}

	@Test("__cswiftslash_threads :: sequence (immediate cancellation)")
	func testThreadCancellationHandlers() {
		let harness = ThreadHarness()
		harness.startThread()
		
		// Cancel the thread
		harness.cancelThread()
		
		// Wait for thread to complete
		harness.joinThread()

		#expect(harness.handlerCalls.count == 3, "expected 3, got \(harness.handlerCalls)")
		#expect(harness.handlerCalls[0] == .allocatorCalled, "expected allocator to be called first")
		#expect(harness.handlerCalls[1] == .cancelCalled, "expected cancel handler to be called second")
		#expect(harness.handlerCalls[2] == .deallocCalled, "expected deallocator to be called last")
	}

	@Test("__cswiftslash_threads :: deallocate short circuit")
	func testDeallocatorAlwaysCalled() {
		let harness = ThreadHarness()
		harness.startThread()
		
		// Cancel the thread immediately
		harness.cancelThread()
		
		// Wait for thread to complete
		harness.joinThread()
		
		// Check that deallocCalled is in the handler calls
		#expect(harness.handlerCalls.contains(.deallocCalled), "Deallocator was not called")
	}

	@Test("__cswiftslash_threads :: deallocate on immediate exit")
	func testDeallocatorCalledOnImmediateExit() {
		let harness = ThreadHarness()
		
		// Modify main function to exit immediately
		harness.run_f = { ws in
			// Exit immediately
			return
		}
		
		harness.startThread()
		harness.joinThread()
		
		// Check that deallocCalled is in the handler calls
		#expect(harness.handlerCalls.contains(.deallocCalled) == true, "deallocator was not called")
	}

	@Test("__cswiftslash_threads :: cancellation after work completion")
	func testCancellationAfterWorkCompletion() {
		let harness = ThreadHarness()
		
		harness.startThread()
		
		// Ensure main function has time to complete
		usleep(1_100_000) // 1s + 100ms
		harness.cancelThread()
		harness.joinThread()
		
		#expect(harness.handlerCalls.count == 3, "expected 3 handler calls, got \(harness.handlerCalls.count)")
		#expect(harness.handlerCalls[0] == .allocatorCalled, "expected allocator to be called first")
		#expect(harness.handlerCalls[1] == .mainCalled, "expected main function to be called second")
		#expect(harness.handlerCalls[2] == .deallocCalled, "expected deallocator to be called last")
		#expect(!harness.handlerCalls.contains(.cancelCalled), "cancel handler should not be called if work is already completed")
	}

	@Test("__cswiftslash_threads :: concurrent threads with cancellation")
	func testConcurrentThreadsWithCancellation() {
		let threadCount = 10
		var harnesses: [ThreadHarness] = []
		
		for _ in 0..<threadCount {
			let harness = ThreadHarness()
			harness.startThread()
			harnesses.append(harness)
		}

		usleep(100_000) // 100ms
		
		// Cancel half of the threads
		for (index, harness) in harnesses.enumerated() {
			if index % 2 == 0 {
				harness.cancelThread()
			}
		}
		
		// Wait for all threads to complete
		for harness in harnesses {
			harness.joinThread()
		}
		
		// Verify handlers for each harness
		for harness in harnesses {
			if harness.handlerCalls.contains(.cancelCalled) {
				// Thread was cancelled
				#expect(harness.handlerCalls.count == 4 || harness.handlerCalls.count == 3, "expected 3 or 4 handler calls for cancelled thread")
				switch harness.handlerCalls.count {
				case 4:
					#expect(harness.handlerCalls[0] == .allocatorCalled, "expected allocator first")
					#expect(harness.handlerCalls[1] == .mainCalled, "expected main function second")
					#expect(harness.handlerCalls[2] == .cancelCalled, "expected cancel handler third")
					#expect(harness.handlerCalls[3] == .deallocCalled, "expected deallocator last")
				case 3:
					#expect(harness.handlerCalls[0] == .allocatorCalled, "expected allocator first")
					#expect(harness.handlerCalls[1] == .cancelCalled, "expected cancel handler second")
					#expect(harness.handlerCalls[2] == .deallocCalled, "expected deallocator last")
				default:
					break
				}
			} else {
				// Thread ran to completion
				#expect(harness.handlerCalls.count == 3, "expected 3 handler calls for completed thread")
				#expect(harness.handlerCalls[0] == .allocatorCalled, "expected allocator first")
				#expect(harness.handlerCalls[1] == .mainCalled, "expected main function second")
				#expect(harness.handlerCalls[2] == .deallocCalled, "expected deallocator last")
			}
		}
	}
}