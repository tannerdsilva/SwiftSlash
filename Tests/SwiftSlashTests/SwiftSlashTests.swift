import XCTest
import Foundation
@testable import SwiftSlash

//MARK: All of this just so that I can print a big red warning in the terminal
fileprivate struct ANSIColorCode {
	static let black = [0, 9]
    static let red = [1, 9]
    static let green = [2, 9]
    static let yellow = [3, 9]
    static let blue = [4, 9]
    static let magenta = [5, 9]
    static let cyan = [6, 9]
    static let white = [7, 9]
}
fileprivate struct ANSIModifiers {
    static var bold = [1, 22]
    static var blink = [5, 25]
    static var dim = [2, 22]
    static var italic = [2, 23]
    static var underline = [4, 24]
    static var inverse = [7, 27]
    static var hidden = [8, 28]
    static var strikethrough = [9, 29]
}

fileprivate func apply<T>(style: [T]) -> ((_:String) -> String) {
	return { str in return "\u{001B}[\(style[0])m\(str)\u{001B}[\(style[1])m" }
}

fileprivate func getColor(color: [Int], mod: Int) -> [Int] {
	let terminator = mod == 30 || mod == 90 ? 30 : 40
	return [ color[0] + mod, color[1] + terminator ]
}

fileprivate class Colors {
    fileprivate static let normalText = 30
    fileprivate static let bg = 40
    fileprivate static let brightText = 90
    fileprivate static let brightBg = 100

    // MARK: 8-bit color functions
    public static func getTextColorer(color: Int) -> ((_:String) -> String) {
        return apply(style:["38;5;\(color)", String(normalText + 9)])
    }

    public static func colorText(text: String, color: Int) -> String {
        return Colors.getTextColorer(color:color)(text)
    }

    public static func getBgColorer(color: Int) -> ((_:String) -> String) {
        return apply(style:["48;5;\(color)", String(bg + 9)])
    }

    public static func colorBg(text: String, color: Int) -> String {
        return Colors.getBgColorer(color:color)(text)
    }

    // MARK: Normal text colors
    public static let black = apply(style:getColor(color:ANSIColorCode.black, mod: normalText))
    public static let red = apply(style:getColor(color:ANSIColorCode.red, mod: normalText))
    public static let green = apply(style:getColor(color:ANSIColorCode.green, mod: normalText))
    public static let yellow = apply(style:getColor(color:ANSIColorCode.yellow, mod: normalText))
    public static let blue = apply(style:getColor(color:ANSIColorCode.blue, mod: normalText))
    public static let magenta = apply(style:getColor(color:ANSIColorCode.magenta, mod: normalText))
    public static let cyan = apply(style:getColor(color:ANSIColorCode.cyan, mod: normalText))
    public static let white = apply(style:getColor(color:ANSIColorCode.white, mod: normalText))

    // MARK: Bright text colors
    public static let Black = apply(style:getColor(color:ANSIColorCode.black, mod: brightText))
    public static let Red = apply(style:getColor(color:ANSIColorCode.red, mod: brightText))
    public static let Green = apply(style:getColor(color:ANSIColorCode.green, mod: brightText))
    public static let Yellow = apply(style:getColor(color:ANSIColorCode.yellow, mod: brightText))
    public static let Blue = apply(style:getColor(color:ANSIColorCode.blue, mod: brightText))
    public static let Magenta = apply(style:getColor(color:ANSIColorCode.magenta, mod: brightText))
    public static let Cyan = apply(style:getColor(color:ANSIColorCode.cyan, mod: brightText))
    public static let White = apply(style:getColor(color:ANSIColorCode.white, mod: brightText))

    // MARK: Normal background colors
    public static let bgBlack = apply(style:getColor(color:ANSIColorCode.black, mod: bg))
    public static let bgRed = apply(style:getColor(color:ANSIColorCode.red, mod: bg))
    public static let bgGreen = apply(style:getColor(color:ANSIColorCode.green, mod: bg))
    public static let bgYellow = apply(style:getColor(color:ANSIColorCode.yellow, mod: bg))
    public static let bgBlue = apply(style:getColor(color:ANSIColorCode.blue, mod: bg))
    public static let bgMagenta = apply(style:getColor(color:ANSIColorCode.magenta, mod: bg))
    public static let bgCyan = apply(style:getColor(color:ANSIColorCode.cyan, mod: bg))
    public static let bgWhite = apply(style:getColor(color:ANSIColorCode.white, mod: bg))

    // MARK: Bright background colors
    public static let BgBlack = apply(style:getColor(color:ANSIColorCode.black, mod: brightBg))
    public static let BgRed = apply(style:getColor(color:ANSIColorCode.red, mod: brightBg))
    public static let BgGreen = apply(style:getColor(color:ANSIColorCode.green, mod: brightBg))
    public static let BgYellow = apply(style:getColor(color:ANSIColorCode.yellow, mod: brightBg))
    public static let BgBlue = apply(style:getColor(color:ANSIColorCode.blue, mod: brightBg))
    public static let BgMagenta = apply(style:getColor(color:ANSIColorCode.magenta, mod: brightBg))
    public static let BgCyan = apply(style:getColor(color:ANSIColorCode.cyan, mod: brightBg))
    public static let BgWhite = apply(style:getColor(color:ANSIColorCode.white, mod: brightBg))

    // MARK: Text modifiers
    public static let bold = apply(style:ANSIModifiers.bold)
    public static let blink = apply(style:ANSIModifiers.blink)
    public static let dim = apply(style:ANSIModifiers.dim)
    public static let italic = apply(style:ANSIModifiers.italic)
    public static let underline = apply(style:ANSIModifiers.underline)
    public static let inverse = apply(style:ANSIModifiers.inverse)
    public static let hidden = apply(style:ANSIModifiers.hidden)
    public static let strikethrough = apply(style:ANSIModifiers.strikethrough)
}

//MARK: Random data generation
extension String {
	//static function that creates a string of random length
	public static func random(length:Int = 32) -> String {
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

//MARK: External processes required for testing
func testWriteProcess(swift:URL) -> String {
	return """
#!\(swift.path)
import Glibc
print(readLine()!)
exit(0)
"""
}

func testExitProcess(swift:URL) -> String {
	return """
#!\(swift.path)
import Glibc
let randomInt = Int32.random(in:1...255)
print(randomInt)
exit(randomInt)
"""
}

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

//MARK: Test case
final class SwiftSlashTests: XCTestCase {
	override class func setUp() {
		print(Colors.bgRed(" - [!WARNING!] - [!WARNING!] - [!WARNING!] - [!WARNING!] - [!WARNING!] - "))
		print(Colors.bgYellow("SwiftSlash unit tests EXTREMELY intense and concurrent in nature. These unit tests are likely to saturate every CPU core on your system. Please refrain from running these tests if your system is in a power concious state.")) 
		print(Colors.bgRed(" - [!WARNING!] - [!WARNING!] - [!WARNING!] - [!WARNING!] - [!WARNING!] - "))
		//set up some test processes that can be launched with SwiftSlash that are designed to help test the internal functionality of the framework
		let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("xctest_swiftslash", isDirectory:true)
		try? FileManager.default.removeItem(at:tempDir)
		try! FileManager.default.createDirectory(at:tempDir, withIntermediateDirectories:true)
		
		//define the paths for these test processes
		let readTestURL = tempDir.appendingPathComponent("readExe.swift", isDirectory:false)
		let writeTestURL = tempDir.appendingPathComponent("writeExe.swift", isDirectory:false)
		let exitTestURL = tempDir.appendingPathComponent("exitExe.swift", isDirectory:false)
		
		//figure out where swift is installed on this system
		let whichSwiftRunResult = try! Command(bash:"which swift").runSync()
		guard whichSwiftRunResult.succeeded == true else {
			exit(5)
		}
		print("PRE UPDATE OUTPUT \(whichSwiftRunResult.stdout.count)")
		let swiftPath = String(data:Data(), encoding:.utf8)!
		guard swiftPath.count > 0 && swiftPath.contains("/") == true else {
			exit(5)
		}
		let swiftURL = URL(fileURLWithPath:swiftPath)
		
		//write the scripts
		try! testReadProcess(swift:swiftURL).data(using:.utf8)!.write(to:readTestURL)
		try! testWriteProcess(swift:swiftURL).data(using:.utf8)!.write(to:writeTestURL)
		try! testExitProcess(swift:swiftURL).data(using:.utf8)!.write(to:exitTestURL)
		
		//make the scripts executable
		guard try! Command(bash:"chmod +x \(readTestURL.path)").runSync().succeeded == true else {
			exit(7)
		}
		guard try! Command(bash:"chmod +x \(writeTestURL.path)").runSync().succeeded == true else {
			exit(7)
		}
		guard try! Command(bash:"chmod +x \(exitTestURL.path)").runSync().succeeded == true else {
			exit(7)
		}
	}
	
	override class func tearDown() {
		let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("xctest_swiftslash", isDirectory:true)
		try! FileManager.default.removeItem(at:tempDir)
	}
	
    func concurrentReadTest() {
    	func singleReaderProcessTest(_ command:Command) -> Bool {
    		do {
				var integerLines = [Int]()
				var didFindExit = false
				let result = try command.runSync()
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
		let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("xctest_swiftslash", isDirectory:true)
		let readTestURL = tempDir.appendingPathComponent("readExe.swift", isDirectory:false)
		let runCommand = Command(bash:"\(readTestURL.path)")
		
		var iterations = 10000
		var successfulAmount = 0
		var sync = DispatchQueue(label:"com.swiftslash.test-serial")
		
        DispatchQueue.concurrentPerform(iterations:iterations) { i in
        	if singleReaderProcessTest(runCommand) == true {
        		sync.sync {
        			successfulAmount += 1
        		}
        	} else {
        		XCTFail("failedReadTest")
        	}
        }
        XCTAssertEqual(iterations, successfulAmount)
    }
    
    func concurrentWriteTest() {
    	func singleWriteProcessTest(_ command:Command, _ randomStringToWrite:String) -> Bool {
    		do {
    			let pi = ProcessInterface(command:command)
    			let writtenData = randomStringToWrite.data(using:.utf8)!
    			var returnedDataCapture = Data()
    			pi.stdoutParseMode = .immediate
    			pi.stdoutHandler = { someData, _ in
    				returnedDataCapture.append(someData)
    			}
    			try pi.run()
    			try pi.write(stdin:writtenData)
    			guard try pi.waitForExitCode() == 0 else {
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
		
		let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("xctest_swiftslash", isDirectory:true)
		let writeTestURL = tempDir.appendingPathComponent("writeExe.swift", isDirectory:false)
		let runCommand = Command(bash:"\(writeTestURL.path)")

    	var iterations = 10000
		var successfulAmount = 0
		var sync = DispatchQueue(label:"com.swiftslash.test-serial")
		
        DispatchQueue.concurrentPerform(iterations:iterations) { i in
			let randomStringToWrite = String.random(length:56000) + "\n"
			for _ in 0..<5 {
				if singleWriteProcessTest(runCommand, randomStringToWrite) == false {
        			XCTFail("failedWriteTest")
        		}
        	}
        	sync.sync {
				successfulAmount += 1
			}
        }
        XCTAssertEqual(iterations, successfulAmount)
    }
    
    func concurrentExitCodeCaptureTest() {
    	func singleExitProcessTest(_ command:Command) -> Bool {
    		do {
    			let result = try command.runSync()
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
    	
    	let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("xctest_swiftslash", isDirectory:true)
		let writeTestURL = tempDir.appendingPathComponent("exitExe.swift", isDirectory:false)
		let runCommand = Command(bash:"\(writeTestURL.path)")

    	var iterations = 10000
		var successfulAmount = 0
		var sync = DispatchQueue(label:"com.swiftslash.test-serial")
		
        DispatchQueue.concurrentPerform(iterations:iterations) { i in
        	if singleExitProcessTest(runCommand) == true {
        		sync.sync {
        			successfulAmount += 1
        		}
        	} else {
        		XCTFail("failedExitTest")
        	}
        }
        XCTAssertEqual(iterations, successfulAmount)
    }

    static var allTests = [
		("concurrentReadTest", concurrentReadTest),
		("concurrentWriteTest", concurrentWriteTest),
		("concurrentExitCodeTest", concurrentExitCodeCaptureTest)
    ]
}