import XCTest
@testable import SwiftSlash

final class InternalSwiftSlashTests:XCTestCase {
	func testEnvironmentVariableRead() throws {
		let curEnv = CurrentProcessState.getCurrentEnvironmentVariables()
		XCTAssert(curEnv.count > 0)
	}

	func testSearchForWhoamIProgram() throws {
		let whoamiPath = try CurrentProcessState.searchCurrentPathsForExecutable("whoami")
		XCTAssert(whoamiPath.hasPrefix("/"))
	}
}
