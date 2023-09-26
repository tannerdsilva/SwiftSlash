import XCTest
@testable import CSwiftSlash

class FutureTests: XCTestCase {
    func testBroadcastCompletion() async throws {
		struct FutureError:Swift.Error {
			let status:UInt8
			let value:Int64
		}

		var myMutex:pthread_mutex_t = pthread_mutex_t()
		pthread_mutex_init(&myMutex, nil)
		defer {
			pthread_mutex_destroy(&myMutex)
		}
        var future = future_int64_t_init()
        
		_ = withUnsafeMutablePointer(to:&future) { futPtr in 
			Task { [fc = futPtr] in
				try await Task.sleep(nanoseconds: 2 * 1_000_000_000) // sleep for 2 seconds
				XCTAssert(future_int64_t_broadcast_res_val(fc, 0, 42) == true)
			}
		}

		// Main thread waits for the future to complete using a continuation
		let completionResult = try await withUnsafeThrowingContinuation { (continuation:UnsafeContinuation<(UInt8, Int64), Swift.Error>) in
			withUnsafeMutablePointer(to:&future) { futPtr in
				future_int64_t_wait_sync(futPtr, &myMutex, { status, value in
					continuation.resume(returning: (UInt8, Int64)(status, value))
				}, { errTyp, errVal in
					continuation.resume(throwing: FutureError(status:errTyp, value:errVal))
				}, {
					continuation.resume(throwing:CancellationError())
				})
			}
		}
		future_int64_t_destroy(&future)
        
        // Check if the future has completed and the result is set correctly
		XCTAssert(completionResult.0 == 0)
		XCTAssert(completionResult.1 == 42)
    }
    
    // func testDoubleBroadcastCompletion() async {
    //     var future = future_t_init()
        
    //     // Complete the future
    //     XCTAssert(future_t_broadcast_completion(&future, 42) == true)
        
    //     // Try to complete the future again
    //     XCTAssert(future_t_broadcast_completion(&future, 100) == false)
        
    //     let isComplete = future_t_wait(&future)
	// 	future_t_release(&future)
	// 	// fatalError("FOO")
	// 	future_t_dealloc(&future)
        
    //     // Check if the future's result hasn't changed
    //     XCTAssert(isComplete == 42)
    // }
}