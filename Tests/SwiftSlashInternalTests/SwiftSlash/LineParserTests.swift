import Testing

@testable import SwiftSlashLineParser

extension Tag {
	@Tag internal static var swiftSlashLineParser:Self
}

extension SwiftSlashTests {
	
	@Suite("SwiftSlashLineParserTests",
		.serialized,
		.tags(.swiftSlashLineParser)
	)
	internal struct LineParserTests {

		@Test("SwiftSlashLineParser :: fuzz testing random data intake with no separator", .timeLimit(.minutes(5)))
		func noSeparatorFuzz() {
			func runNumberOfHandleCalls(_ numberOfHandles:Int32) {
				var readLines = [[UInt8]]()
				var parser = LineParser(separator:[], handler: { newLines in
					if let hasNewLines = newLines {
						readLines.append(contentsOf:hasNewLines)
					}
				})
				var writeLines = [String]()
				for _ in 0..<numberOfHandles {
					let data:[UInt8]
					switch Bool.random() {
						case true:
							data = Array(String.random(length:Int.random(in:1..<1024)).utf8)
							#expect(parser.intake(data) == data.count)
						case false:
							#expect(parser.intake([UInt8]()) == 0)
							data = [UInt8]()
					}
					writeLines.append(String(bytes:data, encoding:.utf8)!)
				}
				parser.finish()
				#expect(readLines.count == numberOfHandles, "\(readLines.count) == \(numberOfHandles)")
				for (index, line) in readLines.enumerated() {
					#expect(line == Array(writeLines[index].utf8), "\(line) == \(Array(writeLines[index].utf8))")
				}
			}
			for _ in 0..<64 {
				runNumberOfHandleCalls(Int32.random(in:2..<1024))
			}
		}
		

		@Test("SwiftSlashLineParser :: fuzz testing random data intake with single separator", .timeLimit(.minutes(5)))
		func singleSeparatorFuzz() {
			func runNumberOfHandleCalls(_ numberOfHandles:Int32) {
				let sep:UInt8 = UInt8.random(in:1..<255)
				var readLines = [[UInt8]]()
				var parser = LineParser(separator:[sep], handler: { newLines in
					if let hasNewLines = newLines {
						readLines.append(contentsOf:hasNewLines)
					}
				})
				var writeLines = [String]()
				for _ in 0..<numberOfHandles {
					let data:[UInt8]
					switch true {
						case true:
							var makeData:[UInt8]
							buildLoop: repeat {
								makeData = Array(String.random(length:Int.random(in:1..<48)).utf8)
								guard makeData.contains(sep) == false else {
									continue buildLoop
								}
								break buildLoop
							} while true
							data = makeData
						case false:
							data = [UInt8]([])
					}
					#expect(parser.intake(data + [sep]) == data.count + 1)
					writeLines.append(String(bytes:data, encoding:.utf8)!)
				}
				parser.finish()
				#expect(readLines == writeLines.map { Array($0.utf8) }, "\(readLines) == \(writeLines.map { Array($0.utf8) })")
			}
			for _ in 0..<512 {
				runNumberOfHandleCalls(Int32.random(in:2..<1024))
			}
		}

		@Test("SwiftSlashLineParser :: handling data with multi-character separator", .timeLimit(.minutes(5)))
		func handleDataWithMultiCharacterSeparator() {
			var lines = [[UInt8]]()
			let separator: [UInt8] = Array("--sep--".utf8)
			var parser = LineParser(separator:separator, handler: { newLines in
				if let hasNewLines = newLines {
					lines.append(contentsOf:hasNewLines)
				}
			})
			let data: [UInt8] = Array("Hello--sep--World".utf8)
			#expect(parser.intake(data) == data.count)
			parser.finish()
			#expect(lines.count == 2, "\(lines.count) == 2")
			#expect(lines[0] == Array("Hello".utf8), "\(lines[0]) == \(Array("Hello".utf8))")
			#expect(String(bytes:lines[1], encoding:.utf8)! == "World", "\(String(bytes:lines[1], encoding:.utf8)!) == World")
		}

		@Test("SwiftSlashLineParser :: repetitive multi-character separator", .timeLimit(.minutes(5)))
		func repetitiveMultiCharacterSeparator() {
			var counter = 0
			var negCounter = 0
			let separator: [UInt8] = Array("--sep--".utf8)
			var parser = LineParser(separator:separator, handler: { newLines in
				if let hasNewLinesMulti = newLines {
					for hasNewLines in hasNewLinesMulti {
						if hasNewLines.count == 0 {
							counter += 1
						} else {
							#expect(Array("-".utf8) == hasNewLines, "\(Array("-".utf8)) == \(hasNewLines)")
							negCounter += 1
						}
					}
				}
			})
			let data: [UInt8] = Array("--sep----sep----sep----sep----sep-----sep----sep----sep----sep--".utf8)
			#expect(parser.intake(data) == data.count)
			#expect(parser.intake(Array("--se".utf8)) == 4)
			#expect(counter == 8, "\(counter) == 8")
			#expect(parser.intake(Array("p--".utf8)) == 3)
			#expect(counter == 9, "\(counter) == 9")
			parser.finish()
			#expect(negCounter == 1, "\(negCounter) == 1")
		}

		@Test("SwiftSlashLineParser :: handling random-length data with random single-byte separator", .timeLimit(.minutes(5)))
		func handleRandomDataWithRandomSingleByteSeparator() {
			var lines = [[UInt8]]()
			let separator = String.random(length: 1)
			var randomStrings = [String]()
			while randomStrings.count < 10 {
				let thisRandomString = String.random(length: Int.random(in:1...256))
				guard thisRandomString.contains(separator) == false else {
					continue
				}
				randomStrings.append(thisRandomString)
			}
			let combinedString = randomStrings.joined(separator:separator)
			var parser = LineParser(separator:Array(separator.utf8), handler: { newLines in
				if let hasNewLines = newLines {
					lines.append(contentsOf:hasNewLines)
				}
			})
			let data: [UInt8] = Array(combinedString.utf8)
			#expect(parser.intake(data) == data.count)
			parser.finish()

			#expect(lines.count == 10, "\(lines.count) == 10")
			for (index, line) in lines.enumerated() {
				#expect(line == Array(randomStrings[index].utf8), "\(line) == \(Array(randomStrings[index].utf8))")
			}
		}

		@Test("SwiftSlashLineParser :: handling random-length data with random multi-byte separator", .timeLimit(.minutes(5)))
		func lineParserFuzz() {
			func lpFuzzIteration() {
				var lines = [[UInt8]]()
				let separator = String.random(length: Int.random(in:1..<16))
				var randomStrings = [String]()
				assembleLoop: while randomStrings.count < 512 {
					let thisRandomString = String.random(length: Int.random(in:256..<1024))
					guard thisRandomString.contains(separator) == false else {
						continue assembleLoop
					}
					randomStrings.append(thisRandomString)
				}
				let combinedString = randomStrings.joined(separator:separator)
				#expect(combinedString.split(separator:separator).count == 512, "\(combinedString.split(separator:separator).count) == 512")
				var parser = LineParser(separator:Array(separator.utf8), handler: { newLines in
					if let hasNewLines = newLines {
						lines.append(contentsOf:hasNewLines)
					}
				})
				let data: [UInt8] = Array(combinedString.utf8)
				#expect(parser.intake(data) == data.count)
				parser.finish()
				#expect(lines == randomStrings.map { Array($0.utf8) }, "\(lines) == \(randomStrings.map { Array($0.utf8) })")
			}
			for _ in 0..<8 {
				lpFuzzIteration()
			}
		}
	}
}