import XCTest

@testable import CSwiftSlash

// this is a workaround for the fact that we can't pass a closure to a C function
let work:@convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? = { arg in
	var myPointer = arg?.bindMemory(to: Bool.self, capacity: 1)
	myPointer?.pointee = true
	return nil
}

func getWorkDone(_ arg:UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
	arg?.assumingMemoryBound(to: Bool.self).pointee = true
	return nil
}

func dontGetWorkDone(_ arg:UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? {
	return nil
}

class WorkThreadTests:XCTestCase {
	func testNoWork() {
		var wt = workthread_t()
		var myBool = false
		withUnsafeMutablePointer(to:&myBool) { arg in
			let launchResult = wt_init(&wt, dontGetWorkDone, arg)
			XCTAssertEqual(launchResult, 0)
		}
		let joinResult = wt_wait(&wt)
		XCTAssertEqual(myBool, false)
		XCTAssertEqual(joinResult, 0)
	}

	func testWork() {
		var wt = workthread_t()
		var myBool = false
		let launchResult = withUnsafeMutablePointer(to:&myBool) { arg in
			wt_init(&wt, getWorkDone, arg)
		}
		XCTAssertEqual(launchResult, 0)
		let joinResult = wt_wait(&wt)
		XCTAssertEqual(myBool, true)
		XCTAssertEqual(joinResult, 0)
	}
}