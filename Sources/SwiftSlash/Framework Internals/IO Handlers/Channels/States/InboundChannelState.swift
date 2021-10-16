import Foundation

internal actor InboundChannelState:Hashable {
	let fh:Int32
	fileprivate var readBlockSize = Int(PIPE_BUF)
	fileprivate var parser:BufferedLineParser
	fileprivate let dataContinuation:AsyncStream<Data>.Continuation
	
	fileprivate var isLaunched = false
	fileprivate var isClosed = false
	fileprivate var didClose = false
	fileprivate var terminationGroup:TerminationGroup
	
	nonisolated internal var hashValue:Int { 
		var hasher = Hasher()
		hasher.combine(fh)
		return hasher.finalize()
	}
	
	init(fh:Int32, group:TerminationGroup, mode:DataParseMode, continuation:AsyncStream<Data>.Continuation) {
		self.fh = fh
		self.parser = BufferedLineParser(mode:mode)
		self.dataContinuation = continuation
		self.terminationGroup = group
	}
	
	func shouldLaunchTask() -> Bool {
		if isLaunched == false {
			isLaunched = true
			return true
		}
		return false
	}
	
	func captureData() async {
		guard isLaunched == false else {
			return
		}
		isLaunched = true
		do {
			var first:Bool = true
			infiniteLoop: repeat {
				let capturedData = try fh.readFileHandle(size:readBlockSize)
				if (isClosed) {
					parser.intake(capturedData)
					for curChunk in parser.flushFinal() {
						self.dataContinuation.yield(curChunk)
					}
					didClose = true
					self.dataContinuation.finish()
					await terminationGroup.removeHandle(fh:self.fh)
					break infiniteLoop
				} else {
					if (capturedData.count == readBlockSize) {
						readBlockSize = readBlockSize * 2
					}
					if parser.intake(capturedData) {
						for curChunk in parser.flushLines() {
							self.dataContinuation.yield(curChunk)
						}
					}
				}
				switch first {
					case false:
						await Task.yield()
					case true:
						first = false
				}
			} while true
		} catch _ {
			if isClosed == true && didClose == false {
				for curChunk in parser.flushFinal() {
					self.dataContinuation.yield(curChunk)
				}
				didClose = true
				self.dataContinuation.finish()
				await terminationGroup.removeHandle(fh:self.fh)
			}
		}
		isLaunched = false
	}
	
	func channelClosed() async {
		isClosed = true
		if isLaunched == false {
			var capturedData = Data()
			do {
				repeat {
					capturedData.append(contentsOf:try fh.readFileHandle(size:readBlockSize))
				} while true
			} catch {}
			parser.intake(capturedData)
			for curChunk in parser.flushFinal() {
				self.dataContinuation.yield(curChunk)
			}
			didClose = true
			self.dataContinuation.finish()
			await terminationGroup.removeHandle(fh:self.fh)
		}
	}
	
	nonisolated func hash(into hasher:inout Hasher) {
		hasher.combine(fh)
	}
	
	static func == (lhs:InboundChannelState, rhs:InboundChannelState) -> Bool {
		return lhs.fh == rhs.fh
	}
}
