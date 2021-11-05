import Foundation

internal actor OutboundChannelState {
	fileprivate var outboundBuffer = Data()
	fileprivate let writeContinuation:AsyncStream<Data>.Continuation
	fileprivate let writeStream:AsyncStream<Data>
	fileprivate let eventStream:AsyncStream<Int32>
	
	internal let continuation:AsyncStream<Int32>.Continuation
	
	fileprivate var fh:Int32? = nil	
	internal func _dataLoop() async {
		for await newData in writeStream {
			self.broadcast(newData)
		}
	}
	internal func _eventLoop() async {
		for await fh in eventStream {
			if self.fh == nil {
				self.fh = fh
			}
			self.flushDataToHandle()
		}
	}
	internal init(channel:DataChannel.Outbound) {
		var eventCont:AsyncStream<Int32>.Continuation? = nil
		let eventStream = AsyncStream<Int32> { cont in
			eventCont = cont
		}
		self.writeStream = channel.stream
		self.eventStream = eventStream
		self.continuation = eventCont!
		self.writeContinuation = channel.continuation
	}
	
	internal func broadcast(_ dataToWrite:Data) {
		outboundBuffer.append(contentsOf:dataToWrite)
		if (self.fh != nil) {
			self.flushDataToHandle()
		}
	}
		
	fileprivate func flushDataToHandle() {
		do {
			while outboundBuffer.count > 0 {
				let remainingData = try self.fh!.writeFileHandle(self.outboundBuffer)
				outboundBuffer.removeAll(keepingCapacity:true)
				if (remainingData.count > 0) {
					outboundBuffer.append(remainingData)
				}
			}
		} catch _ {}
	}
	
	nonisolated internal func terminateLoop() {
		writeContinuation.finish()
		continuation.finish()
	}
}
