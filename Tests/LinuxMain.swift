import XCTest

import SwiftSlashTests

let testWriteScript = """
#! swift path
import Glibc
print(readLine()!)
exit(0)
"""

let testExitScript = """
#! swift path
import Glibc
let randomInt = Int32.random(in:1...255)
print(randomInt)
exit(randomInt)
"""

let testReadScript = """
#! swift path
for i in 0..<10000 {
	print("\(i)")
}
defer {
	print("ex")
}
"""

var tests = [XCTestCaseEntry]()
tests += SwiftSlashTests.allTests()
XCTMain(tests)
