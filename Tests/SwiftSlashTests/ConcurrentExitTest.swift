import XCTest
@testable import SwiftSlash

func testExitProcess(swift:URL) -> String {
    return """
    #!\(swift.path)
    #if os(Linux)
    import Glibc
    #elseif os(macOS)
    import Darwin
    #endif
    let randomInt = Int32.random(in:1...255)
    print(randomInt)
    exit(randomInt)
    """
}

final class ConcurrentExitTest:XCTestCase {
    func testConcurrentExits() async {

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("xctest_swiftslash", isDirectory:true)
        try? FileManager.default.removeItem(at:tempDir)
        try! FileManager.default.createDirectory(at:tempDir, withIntermediateDirectories:true)
        let exitTestURL = tempDir.appendingPathComponent("exitExe.swift", isDirectory:false)
        let whichSwift = URL(fileURLWithPath:String(data:try! await Command(bash:"which swift").runSync().stdout[0], encoding:.utf8)!)
        try! testExitProcess(swift:whichSwift).data(using:.utf8)!.write(to:exitTestURL)
        guard try! await Command(bash:"chmod +x \(exitTestURL.path)").runSync().succeeded == true else {
            exit(7)
        }

        @Sendable func singleExitProcessTest(_ command:Command) async -> Bool {
            do {
                let result = try await command.runSync()
                let allData = String(data:result.stdout.reduce(Data(), +), encoding:.utf8)!
                let integerData = Int32(allData)!
                if (integerData == result.exitCode) {
                    return true
                } else {
                    return false
                }
            } catch {
                return false
            }
        }
        
        let runCommand = Command(bash:"\(exitTestURL.path)")
        let iterations = 100
        var successfulAmount = await withTaskGroup(of:Bool.self, returning:Int.self, body: { tg in
            for _ in 0..<iterations {
                tg.addTask {
                    return await singleExitProcessTest(runCommand)
                }
            }
            var countIt = 0
            for await result in tg {
                if result == true {
                    countIt += 1
                } else {
                    try? FileManager.default.removeItem(at:tempDir)
                    XCTFail("inconsistent exit code")
                }
            }
            return countIt
        })
        
        try? FileManager.default.removeItem(at:tempDir)
        XCTAssertEqual(iterations, successfulAmount)
    }
}
