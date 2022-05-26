import XCTest
@testable import SwiftSlash
@testable import ClibSwiftSlash

final class SwiftSlashInternalTests:XCTestCase {
	func testFDResourceUtilization() {
		var getUsed:Double = 0;
		var getTotal:Double = 0;
		guard getfdlimit(&getUsed, &getTotal) == 0 else {
			XCTFail();
			return
		}
		_ = open("/dev/null", 0);
		var newUsed:Double = 0;
		var newTotal:Double = 0;
		guard getfdlimit(&newUsed, &newTotal) == 0 else {
			XCTFail();
			return
		}
		XCTAssert((getUsed + 1) == newUsed)
	}
}
