import Foundation

internal actor OutboundChannelState:Hashable {
	internal let fh:Int32
	fileprivate var outboundBuffer = Data()
	internal let terminationGroup:TerminationGroup
	
	nonisolated internal var hashValue:Int {
		var hasher = Hasher()
		hasher.combine(fh)
		return hasher.finalize()
	}
	
	internal init(fh:Int32, group:TerminationGroup) {
		self.fh = fh
		self.terminationGroup = group
	}
	
	internal func broadcast(_ dataToWrite:Data) {
		outboundBuffer.append(contentsOf:dataToWrite)
		self.flushDataToHandle()
	}
	
	internal func channelWritableEvent() {
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
		} catch _ {}
	}
	
	nonisolated func hash(into hasher:inout Hasher) {
		hasher.combine(fh)
	}
	
	static func == (lhs:OutboundChannelState, rhs:OutboundChannelState) -> Bool {
		return lhs.fh == rhs.fh
	}
}
