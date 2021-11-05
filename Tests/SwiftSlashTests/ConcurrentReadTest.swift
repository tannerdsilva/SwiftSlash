import XCTest
@testable import SwiftSlash

func testReadProcess(swift:URL) -> String {
    return """
#!\(swift.path)
for i in 0..<10000 {
    print("\\(i)")
}
defer {
    print("ex")
}
"""
}

final class ConcurrentReadTest:XCTestCase {
    func testConcurrentReads() async {
        //setup
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("xctest_swiftslash", isDirectory:true)
        try? FileManager.default.removeItem(at:tempDir)
        try! FileManager.default.createDirectory(at:tempDir, withIntermediateDirectories:true)
        let readTestURL = tempDir.appendingPathComponent("readExe.swift", isDirectory:false)
        let whichSwift = URL(fileURLWithPath:String(data:try! await Command(bash:"which swift").runSync().stdout[0], encoding:.utf8)!)
        try! testReadProcess(swift:whichSwift).data(using:.utf8)!.write(to:readTestURL)
        guard try! await Command(bash:"chmod +x \(readTestURL.path)").runSync().succeeded == true else {
            exit(7)
        }
        
        //run the test
        @Sendable func singleReaderProcessTest(_ command:Command) async -> Bool {
            do {
                var integerLines = [Int]()
                var didFindExit = false
                let result = try await command.runSync()
                guard result.succeeded == true else {
                    return false
                }
                lineLoop: for curLine in result.stdout {
                    if let lineString = String(data:curLine, encoding:.utf8) {
                        if lineString == "ex" {
                            didFindExit = true
                            break lineLoop;
                        } else if (didFindExit == false) {
                            if let lineInt = Int(lineString) {
                                if integerLines.count == 0 || integerLines.last! == lineInt-1 {
                                    integerLines.append(lineInt)
                                }
                            } else {
                                return false
                            }
                        }
                    }
                }
                if integerLines.count == 10000 && didFindExit == true {
                    return true
                } else {
                    return false
                }
            } catch {
                return false
            }
        }
        let runCommand = Command(bash:"\(readTestURL.path)")
        let iterations = 100
        let successfulAmount = await withTaskGroup(of:Bool.self, returning:Int.self, body: { tg in
            for _ in 0..<iterations {
                tg.addTask {
                    return await singleReaderProcessTest(runCommand)
                }
            }
            var successfulIterations = 0
            for await result in tg {
                if result == true {
                    successfulIterations += 1
                } else {
                    try? FileManager.default.removeItem(at:tempDir)
                    XCTFail("failedReadTest")
                }
            }
            return successfulIterations
        })
        
        //cleanup
        try? FileManager.default.removeItem(at:tempDir)
        XCTAssertEqual(iterations, successfulAmount)
    }
}
