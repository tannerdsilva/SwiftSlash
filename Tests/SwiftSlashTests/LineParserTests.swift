import XCTest
@testable import SwiftSlash

class LineParserTests: XCTestCase {

	// Test handling data with no separator configuration.
	func testHandleDataWithNoSeparator() {
		var lines = [Bytes]()
		let output: LineParser.Output = .handler { newLines in
			lines.append(contentsOf:newLines)
		}

		var parser = LineParser(configuration: .noSeparator, output: output)
		var data: [UInt8] = Array("Hello World".utf8)
		parser.handle(&data)
		parser.finish()
		XCTAssertEqual(lines.count, 1)
	}

	// Test handling data with separator configuration.
	func testHandleDataWithSeparator() {
		var lines = [Bytes]()
		let output: LineParser.Output = .handler { newLines in
			lines.append(contentsOf: newLines)
		}
		let separator: [UInt8] = [10] // ASCII for newline
		var parser = LineParser(configuration: .withSeparator(separator), output: output)
		var data: [UInt8] = Array("Hello\nWorld".utf8)
		parser.handle(&data)
		parser.finish()
		XCTAssertEqual(lines.count, 2)
	}

	// Test handling data with multi-character separator configuration.
	func testHandleDataWithMultiCharacterSeparator() {
		var lines = [Bytes]()
		let output: LineParser.Output = .handler { newLines in
			lines.append(contentsOf: newLines)
		}
		let separator: [UInt8] = Array("--sep--".utf8)
		var parser = LineParser(configuration: .withSeparator(separator), output: output)
		var data: [UInt8] = Array("Hello--sep--World".utf8)
		parser.handle(&data)
		parser.finish()
		XCTAssertEqual(lines.count, 2)
	}

	// Test handling random-length data with random single-byte separator.
	func testHandleRandomDataWithRandomSingleByteSeparator() {
		var lines = [Bytes]()
		let output: LineParser.Output = .handler { newLines in
			lines.append(contentsOf: newLines)
		}
		let separator = String.randomSeparator(length: 1)
		let randomStrings = (0..<10).map { _ in String.random(length: Int.random(in: 1...10)) }
		let combinedString = randomStrings.joined(separator:separator)
		var parser = LineParser(configuration: .withSeparator(Array(separator.utf8)), output: output)
		var data: [UInt8] = Array(combinedString.utf8)
		parser.handle(&data)
		parser.finish()

		XCTAssertEqual(lines.count, 10)
		for (index, line) in lines.enumerated() {
			XCTAssertEqual(line, Array(randomStrings[index].utf8))
		}
	}

	// Test handling random-length data with random multi-byte separator.
	func testHandleRandomDataWithRandomMultiByteSeparator() {
		var lines = [Bytes]()
		let output: LineParser.Output = .handler { newLines in
			lines.append(contentsOf: newLines)
		}
		let separator = String.randomSeparator(length: Int.random(in: 1...10))
		let randomStrings = (0..<10).map { _ in String.random(length: Int.random(in: 1...10)) }
		let combinedString = randomStrings.joined(separator:separator)
		var parser = LineParser(configuration: .withSeparator(Array(separator.utf8)), output: output)
		var data: [UInt8] = Array(combinedString.utf8)
		parser.handle(&data)
		parser.finish()

		XCTAssertEqual(lines.count, 10)
		for (index, line) in lines.enumerated() {
			XCTAssertEqual(line, Array(randomStrings[index].utf8))
		}
	}
}


extension String {
	static func randomSeparator(length: Int) -> String {
		let characters = "!@#$%^&*()_+=-`~/?.>,<;:'\""
		return String((0..<length).map { _ in characters.randomElement()! })
	}
	// Utility function to generate a random string of given length
	static func random(length: Int) -> String {
		let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
		return String((0..<length).map { _ in characters.randomElement()! })
	}
}
