import Foundation

actor OutboundChannelState:Hashable {
	let fh:Int32
	var outboundBuffer = Data()
	
	nonisolated internal var hashValue:Int {
		var hasher = Hasher()
		hasher.combine(fh)
		return hasher.finalize()
	}
	
	init(fh:Int32) {
		self.fh = fh
	}
	
	func broadcast(_ dataToWrite:Data) {
		outboundBuffer.append(contentsOf:dataToWrite)
		self.flushDataToHandle()
	}
	
	func channelWritableEvent() {
		self.flushDataToHandle()
	}
	
	fileprivate func flushDataToHandle() {
		do {
			while outboundBuffer.count > 0 {
				let remainingData = try self.fh.writeFileHandle(self.outboundBuffer)
				outboundBuffer.removeAll(keepingCapacity:true)
				if (remainingData.count > 0) {
					outboundBuffer.append(remainingData)
				}
			}
		} catch FileHandleError.error_again {
		} catch FileHandleError.error_wouldblock {
		} catch FileHandleError.error_pipe {
		} catch _ {}
	}
	
	nonisolated func hash(into hasher:inout Hasher) {
		hasher.combine(fh)
	}
	
	static func == (lhs:OutboundChannelState, rhs:OutboundChannelState) -> Bool {
		return lhs.fh == rhs.fh
	}
}