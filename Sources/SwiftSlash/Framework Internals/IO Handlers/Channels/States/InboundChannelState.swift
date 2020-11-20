import Foundation

class InboundChannelState:Hashable {
	let fh:Int32
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
	
	func capture(data capturedData:Data, terminate:Bool) {
		var didFire = false
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
		if terminate && !didFire {
			for (_, curChunk) in parser.flushFinal().enumerated() {
				self.dataHandler(curChunk)
			}
		}
	}
}
