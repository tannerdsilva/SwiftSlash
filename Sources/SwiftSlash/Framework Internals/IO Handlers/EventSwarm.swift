import Foundation

internal struct EventSwarm {
	internal static let global = EventSwarm()

	fileprivate let eventTrigger:EventTrigger
	fileprivate let channelManager:ChannelManager
	
	fileprivate init() {
		let cm = ChannelManager()
		self.channelManager = cm
		self.eventTrigger = EventTrigger.launchNew({ fh, mode in
			Task.detached { [fh, mode] in
				await cm.handleEvent(fh:fh, event:mode)
			}
		})
	}
	
	internal func register(readers:[ReadableConfiguration], writer:WritableConfiguration) async throws -> OutboundChannelState {
		try eventTrigger.register(writer:writer.fh)
		for (_, curReader) in readers.enumerated() {
			try eventTrigger.register(reader:curReader.fh)
		}
		return await channelManager.register(readers:readers, writer:writer)
	}
}