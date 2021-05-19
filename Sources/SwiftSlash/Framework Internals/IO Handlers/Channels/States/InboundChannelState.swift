import Foundation

class InboundChannelState:Hashable {
	let fh:Int32
	var readBlockSize = Int(PIPE_BUF)
	var parser:BufferedLineParser
	let dataHandler:InboundDataHandler
	
	init(fh:Int32, mode:DataParseMode, dataHandler:@escaping(InboundDataHandler)) {
		self.fh = fh
		self.dataHandler = dataHandler
		self.parser = BufferedLineParser(mode:mode)
	}
	
	static func == (lhs:InboundChannelState, rhs:InboundChannelState) -> Bool {
		return lhs.fh == rhs.fh
	}
	
	func hash(into hasher:inout Hasher) {
		hasher.combine(fh)
	}
	
	func captureData(terminate:Bool) -> Bool {
		var isReadable = true
		var didFire = false
		var capturedData = Data()
		do {
			repeat {
				try capturedData.append(fh.readFileHandle(size:readBlockSize))
			} while terminate == true
		} catch FileHandleError.error_again {
			isReadable = false
		} catch FileHandleError.error_wouldblock {
			isReadable = false
		} catch FileHandleError.error_pipe {
		} catch _ {
		}
		if (capturedData.count == readBlockSize) && (terminate == false) {
			readBlockSize = readBlockSize * 2
		}
		if (capturedData.count > 0) {
			if (parser.intake(capturedData)) {
				if (terminate) {
					for (_, curChunk) in parser.flushFinal().enumerated() {
						self.dataHandler(curChunk)
					}
				} else {
					for (_, curChunk) in parser.flushLines().enumerated() {
						self.dataHandler(curChunk)
					}
				}
				didFire = true
			}
		}
		if terminate && !didFire {
			for (_, curChunk) in parser.flushFinal().enumerated() {
				self.dataHandler(curChunk)
			}
		}
		return isReadable
	}
}
