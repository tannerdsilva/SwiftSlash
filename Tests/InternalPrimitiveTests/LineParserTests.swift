import XCTest
@testable import SwiftSlashLineParser
@testable import SwiftSlashNAsyncStream

class LineParserTests: XCTestCase {

	// Test handling data with no separator configuration.
	func testNoSeparatorFuzz() {
		func runNumberOfHandles(number:size_t) {
			var readLines = [[UInt8]]()
			var parser = LineParser(separator:[], handler: { newLines in
				if let hasNewLines = newLines {
					readLines.append([UInt8](hasNewLines))
				}
			})
			var writeLines = [String]()
			for _ in 0..<number {
				let data:[UInt8]
				switch Bool.random() {
					case true:
						data = Array(String.random(length:Int.random(in:1..<1024)).utf8)
						parser.handle(data)
					case false:
						parser.handle([UInt8]())
						data = [UInt8]()
				}
				writeLines.append(String(bytes:data, encoding:.utf8)!)
			}
			parser.finish()
			XCTAssertEqual(readLines.count, number)
			for (index, line) in readLines.enumerated() {
				XCTAssertEqual(line, Array(writeLines[index].utf8))
			}
		}
		for _ in 0..<64 {
			runNumberOfHandles(number:Int.random(in:2..<1024))
		}
	}

	// Test handling data with no separator configuration.
	func testSingleSeparatorFuzz() {
		func runNumberOfHandles(number:size_t) {
			let sep:UInt8 = 10
			var readLines = [[UInt8]]()
			var parser = LineParser(separator:[sep], handler: { newLines in
				if let hasNewLines = newLines {
					print("got line \(hasNewLines)")
					readLines.append([UInt8](hasNewLines))
				}
			})
			var writeLines = [String]()
			for _ in 0..<number {
				print("ITERATING")
				let data:[UInt8]
				switch Bool.random() {
					case true:
						var makeData:[UInt8]
						buildLoop: repeat {
							makeData = Array(String.random(length:Int.random(in:1..<48)).utf8)
							guard makeData.contains(sep) == false else {
								continue buildLoop
							}
							break buildLoop
						} while true
						defer {
							print("EXIT")
						}
						parser.handle(makeData + [sep])
						data = makeData
					case false:
						parser.handle([UInt8]([sep]))
						data = [UInt8]([])
						print("writing line terminator")
				}
				writeLines.append(String(bytes:data, encoding:.utf8)!)
			}
			// parser.finish()
			XCTAssertEqual(readLines.count, number)
			for (index, line) in readLines.enumerated() {
				// XCTAssertEqual(line, Array(writeLines[index].utf8))
			}
		}
		for _ in 0..<1 {
			runNumberOfHandles(number:2)
		}
	}

	// Test handling data with multi-character separator configuration.
	/*func testHandleDataWithMultiCharacterSeparator() {
		var lines = [[UInt8]]()
		let separator: [UInt8] = Array("--sep--".utf8)
		var parser = LineParser(separator:separator, handler: { newLines in
			if let hasNewLines = newLines {
				lines.append([UInt8](hasNewLines))
			}
		})
		let data: [UInt8] = Array("Hello--sep--World".utf8)
		parser.handle(data)
		parser.finish()
		XCTAssertEqual(lines.count, 2)
		XCTAssertEqual(lines[0], Array("Hello".utf8))
		XCTAssertEqual(lines[1], Array("World".utf8))
		fatalError("'\(String(describing:String(bytes: lines[0], encoding: .utf8)))'")
	}*/

	// // Test handling random-length data with random single-byte separator.
	/*func testHandleRandomDataWithRandomSingleByteSeparator() {
		var lines = [[UInt8]]()
		let separator = String.random(length: 1)
		var randomStrings = [String]()
		while randomStrings.count < 10 {
			let thisRandomString = String.random(length: Int.random(in: 1...256))
			guard thisRandomString.contains(separator) == false else {
				continue
			}
			randomStrings.append(thisRandomString)
		}
		let combinedString = randomStrings.joined(separator:separator)
		var parser = LineParser(separator:Array(separator.utf8), handler:  { newLines in
			if let hasNewLines = newLines {
				lines.append([UInt8](hasNewLines))
			}
		})
		let data: [UInt8] = Array(combinedString.utf8)
		parser.handle(data)
		parser.finish()

		XCTAssertEqual(lines.count, 10)
		for (index, line) in lines.enumerated() {
			XCTAssertEqual(line, Array(randomStrings[index].utf8))
		}
	}
*/
	// // Test handling random-length data with random multi-byte separator.
/*	func testLineParserFuzz() {
		var lines = [[UInt8]]()
		let separator = String.random(length: Int.random(in: 1...10))
		var randomStrings = [String]()
		while randomStrings.count < 512 {
			let thisRandomString = String.random(length: Int.random(in: 1...256))
			guard thisRandomString.contains(separator) == false else {
				continue
			}
			randomStrings.append(thisRandomString)
		}
		let combinedString = randomStrings.joined(separator:separator)
		XCTAssertEqual(combinedString.split(separator:separator).count, 512)
		var parser = LineParser(separator:Array(separator.utf8), handler: { newLines in
			if let hasNewLines = newLines {
				lines.append([UInt8](hasNewLines))
			}
		})
		let data: [UInt8] = Array(combinedString.utf8)
		parser.handle(data)
		parser.finish()

		XCTAssertEqual(lines.count, 512)
		// return
		for (index, line) in lines.enumerated() {
			XCTAssertEqual(line, Array(randomStrings[index].utf8))
			XCTAssertEqual(line, Array(randomStrings[index].utf8))
		}
	}
	*/
}

extension String {
	// Utility function to generate a random string of given length
	static func random(length: Int) -> String {
		let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+=-`~/?.>,<;:'\""
		return String((0..<length).map { _ in characters.randomElement()! })
	}
}
