import Foundation

class EventSwarm {
	static let global = EventSwarm()
	
	let loopQueue = DispatchQueue(label:"com.swiftslash.events.trigger", attributes:[.concurrent], target:process_master_queue)
	
	let eventTrigger = EventTrigger()
	let channelManager = ChannelManager()
	
	init() {
		self.eventTrigger.channelManager = self.channelManager
		self.channelManager.eventTrigger = self.eventTrigger
		
		loopQueue.async { [et = self.eventTrigger] in
			et._mainLoop()
		}
		
		loopQueue.async { [cm = self.channelManager] in
			cm._mainLoop()
		}
	}
	
	func register(readers:[ReadableConfiguration], writer:WritableConfiguration) throws -> OutboundChannelState {
		try eventTrigger.register(writer:writer.fh)
		for (_, curReader) in readers.enumerated() {
			try eventTrigger.register(reader:curReader.fh)
		}
		return channelManager.register(readers:readers, writer:writer)
	}
}