import XCTest
@testable import SwiftSlash

class PathTests: XCTestCase {

    func testInitWithPathString() {
        let pathString = "/Users/username/Documents"
        let path = Path(pathString)
        XCTAssertEqual(path.path(), pathString)
    }
	
    func testAppendingPathComponent() {
        var path = Path("/Users")
        path.appendPathComponent("username")
        XCTAssertEqual(path.path(), "/Users/username")
    }

    func testAppendingPathComponentWithEmptyString() {
        var path = Path("/Users")
        path.appendPathComponent("")
        XCTAssertEqual(path.path(), "/Users/")
    }

    func testRemoveLastComponent() {
        var path = Path("/Users/username/Documents")
        path.removeLastComponent()
        XCTAssertEqual(path.path(), "/Users/username")
    }

    func testPath() {
        let pathString = "/Users/username/Documents"
        let path = Path(pathString)
        XCTAssertEqual(String(path), pathString)
    }
}