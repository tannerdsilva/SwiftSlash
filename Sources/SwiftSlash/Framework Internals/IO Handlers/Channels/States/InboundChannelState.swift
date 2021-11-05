import Foundation

internal actor InboundChannelState {	
	fileprivate var parser:BufferedLineParser
	fileprivate let dataContinuation:AsyncStream<Data>.Continuation
	fileprivate let eventStream:AsyncStream<Data>
	internal let eventContinuation:AsyncStream<Data>.Continuation
	
	internal init(mode:DataChannel.Inbound.ParseMode, continuation:AsyncStream<Data>.Continuation) {
		var eventCont:AsyncStream<Data>.Continuation? = nil
		let eventStream = AsyncStream<Data> { cont in
			eventCont = cont
		}
		self.parser = BufferedLineParser(mode:mode)
		self.dataContinuation = continuation
		self.eventStream = eventStream
		self.eventContinuation = eventCont!
	}
	
	internal func _mainLoop() async {
		for await capturedData in eventStream {
			if parser.intake(capturedData) {
				for curChunk in parser.flushLines() {
					self.dataContinuation.yield(curChunk)
				}
			}
		}
		self.dataContinuation.finish()
	}
	
	nonisolated internal func terminateLoop() {
		self.eventContinuation.finish()
	}
}
