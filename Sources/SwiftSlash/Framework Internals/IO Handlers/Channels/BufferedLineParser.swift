import Foundation

internal struct BufferedLineParser {
	internal var type:DataParseMode
	
	fileprivate var currentLine = Data()
	fileprivate var pendingLines = [Data]()
	
	init() {
		self.type = .lf
	}
	
	init(mode:DataParseMode) {
		self.type = mode
	}
	
	@discardableResult mutating func intake(_ dataToIntake:Data) -> Bool {
		var didFind = false
		var crLast = false
		if (self.type == .immediate) {
			pendingLines.append(dataToIntake)
			return true
		}
		dataToIntake.withUnsafeBytes { unsafeBytes in
			var i = 0
			while (i < dataToIntake.count) {
				defer {
					i = i + 1
				}
				let curByte = unsafeBytes[i]
				switch type {
					case .cr:
						if (curByte == 13) {
							pendingLines.append(currentLine)
							currentLine.removeAll(keepingCapacity:true)
							didFind = true
						} else {
							currentLine.append(curByte)
						}
					case .lf:
						if (curByte == 10) {
							pendingLines.append(currentLine)
							currentLine.removeAll(keepingCapacity:true)
							didFind = true
						} else {
							currentLine.append(curByte)
						}
					case .crlf:
						if (crLast == true && curByte == 10) {
							crLast = false
							pendingLines.append(currentLine)
							currentLine.removeAll(keepingCapacity:true)
							didFind = true
						} else if (crLast == false && curByte == 13) {
							crLast = true
						} else {
							if (crLast == true) {
								currentLine.append(13)
							}
							crLast = false
							currentLine.append(curByte)
						}
					default:
						break
				}
			}
		}
		return didFind
	}
	
	mutating func flushLines() -> [Data] {
		let pendingLinesCopy = self.pendingLines
		self.pendingLines.removeAll()
		return pendingLinesCopy
	}
	
	mutating func flushFinal() -> [Data] {
		let currentLineCopy = self.currentLine
		self.currentLine.removeAll(keepingCapacity:false)
		var returnLines = self.pendingLines
		self.pendingLines.removeAll()
		if (currentLineCopy.count > 0) {
			returnLines.append(currentLineCopy)
		}
		return returnLines
	}
}
