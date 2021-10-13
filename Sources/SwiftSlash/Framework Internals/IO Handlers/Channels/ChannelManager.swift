import Foundation

internal actor ChannelManager {
	fileprivate var readers = [Int32:InboundChannelState]()
	fileprivate var writers = [Int32:OutboundChannelState]()
	
	internal func register(readers:[ReadableConfiguration], writer:WritableConfiguration) -> OutboundChannelState {
		for (_, curReadable) in readers.enumerated() {
			let newConfig = InboundChannelState(fh:curReadable.fh, group:curReadable.group, mode:curReadable.parseMode, dataHandler:curReadable.handler)
			_ = self.readers.updateValue(newConfig, forKey:curReadable.fh)
		}
		let newWriter = OutboundChannelState(fh:writer.fh, group:writer.group)
		_ = self.writers.updateValue(newWriter, forKey:writer.fh)
		return newWriter
	}
	
	internal func handleEvent(fh:Int32, event:EventMode) async {
		switch event {
			case .readableEvent:
				let curReader = readers[fh]!
				await curReader.captureData()
			case .readingClosed:
				let curReader = readers[fh]!
				await curReader.channelClosed()
				self.readers.removeValue(forKey:fh)
			case .writingClosed:
				let curWriter = writers[fh]!
				await curWriter.terminationGroup.removeHandle(fh:fh)
				self.writers.removeValue(forKey:fh)
				break;
			case .writableEvent:
				let curWriter = writers[fh]!
				await curWriter.channelWritableEvent()
			break;
		}
	}
}