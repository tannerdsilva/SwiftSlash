
import XCTest
@testable import SwiftSlash

func testWriteProcess(swift:URL) -> String {
    return """
    #!\(swift.path)
    print(readLine()!)
    """
}

extension String {
    //static function that creates a string of random length
    static func random(length:Int = 32) -> String {
        let base = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let baseLength = base.count
        var randomString = ""
        for _ in 0..<length {
            let randomIndex = Int.random(in:0..<baseLength)
            randomString.append(base[base.index(base.startIndex, offsetBy:randomIndex)])
        }
        return randomString
    }
}


final class ConcurrentWriteTest:XCTestCase {
    func testConcurrentWrites() async {
        //setup
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("xctest_swiftslash", isDirectory:true)
        try? FileManager.default.removeItem(at:tempDir)
        try! FileManager.default.createDirectory(at:tempDir, withIntermediateDirectories:true)
        let writeTestExe = tempDir.appendingPathComponent("writeExe.swift", isDirectory:false)
        let whichSwift = URL(fileURLWithPath:String(data:try! await Command(bash:"which swift").runSync().stdout[0], encoding:.utf8)!)
        try! testWriteProcess(swift:whichSwift).data(using:.utf8)!.write(to:writeTestExe)
        guard try! await Command(bash:"chmod +x \(writeTestExe.path)").runSync().succeeded == true else {
            exit(7)
        }
        @Sendable func singleWriteProcessTest(_ command:Command, _ randomStringToWrite:String) async -> Bool {
                    do {
                        let pi = ProcessInterface(command:command, stdout:.active(.unparsedRaw), stderr:.active(.unparsedRaw))
                        let writtenData = randomStringToWrite.data(using:.utf8)!
                        var returnedDataCapture = Data()
                        async let exitCode = try pi.exitCode()
                        await pi.write(stdin:writtenData)
                        for await data in await pi.stdout {
                            returnedDataCapture += data
                        }
                        guard try! await exitCode == 0 else {
                            return false
                        }
                        if (returnedDataCapture == writtenData) {
                            return true
                        } else {
                            return false
                        }
                    } catch {
                        return false
                    }
                }
        let runCommand = Command(bash:"\(writeTestExe.path)")
        let iterations = 250
        let successfulAmount = await withTaskGroup(of:Bool.self, returning:Int.self, body: { tg in
                
            for _ in 0..<iterations {
                tg.addTask {
                    let randomStringToWrite = String.random(length:750) + "\n"
                    return await singleWriteProcessTest(runCommand, randomStringToWrite)
                }
            }
            var countSuccess = 0
            for await result in tg {
                if result == true {
                    countSuccess += 1
                } else {
                    try? FileManager.default.removeItem(at:tempDir)
                    fatalError("written echo test failed")
                }
            }
            await tg.waitForAll()
            return countSuccess
        })
        
        try? FileManager.default.removeItem(at:tempDir)
        XCTAssertEqual(iterations, successfulAmount)
    }
}
