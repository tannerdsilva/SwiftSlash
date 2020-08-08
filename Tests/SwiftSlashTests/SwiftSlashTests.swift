import XCTest
@testable import SwiftSlash

final class SwiftSlashTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(SwiftSlash().text, "Hello, World!")
    }

    static var allTests = [
        ("testExample", testExample),
    ]
}
