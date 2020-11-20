import Foundation

class DownstreamHandler {
	let internalSync = DispatchQueue(label:"com.swiftslash.downstream-handler.sync", target:process_master_queue)
	
	var datas = [Int32:Data]()
	var closed = Set<Int32>()
	var readers = [Int32:InboundChannelState]()
	var groups = [Int32:TerminationGroup]()
	
	var loopEnabled = false
	let loopGroup = DispatchGroup()
	
	init() {
		loopGroup.enter()
	}
	
	//this is a function that ensures that the main loop stops running if there are no shell instances active
	fileprivate func _adjustLoopGroupState() {
		if (self.datas.count == 0 && self.closed.count == 0 && loopEnabled == true) {
			loopEnabled = false
			loopGroup.enter() //pause the loop by entering the loop group
		} else if (self.datas.count > 0 || self.closed.count > 0) && (loopEnabled == false) {
			loopEnabled = true
			loopGroup.leave() //resume the loop by leaving the loop group
		}
	}
	
	//extraction point for main loop (defines that data that the main loop work upon)
	fileprivate struct ExtractionPackage {
		let master:Set<Int32>
		let datas:[Int32:Data]
		let closed:Set<Int32>
		let readers:[Int32:InboundChannelState]
		let groups:[Int32:TerminationGroup] 
	}
	fileprivate func extractEvents() -> ExtractionPackage {
		return self.internalSync.sync {
			
			//copy all the present data for this sync state
			let captureDatas = self.datas
			let captureClosed = self.closed
			let captureReaders = self.readers
			let captureGroups = self.groups
			
			//acts as the primary set of file descriptors that the main loop is to concurrently iterate through
			var buildMaster = Set<Int32>()
			buildMaster.formUnion(captureDatas.keys)
			buildMaster.formUnion(captureClosed)
			
			self._adjustLoopGroupState()
			
			//remove all the pending data before dropping this sync state
			self.datas.removeAll(keepingCapacity:true)
			self.closed.removeAll(keepingCapacity:true)
			for (_, curClosed) in captureClosed.enumerated() {
				_ = self.readers.removeValue(forKey:curClosed)
				_ = self.groups.removeValue(forKey:curClosed)
			}
			
			return ExtractionPackage(master:buildMaster, datas:captureDatas, closed:captureClosed, readers:captureReaders, groups:captureGroups)
		}
	}
	
	//input function
	func intake(capturedEvents:[ChannelManager.CapturedHandleEvent]) {
		self.internalSync.sync {
			for (_, curEvent) in capturedEvents.enumerated() {
				//was this file handle closed? if so, add it to the set of closed file handles
				if (curEvent.closed == true) {
					_ = self.closed.update(with:curEvent.fh)
				}
				//is there captured data that needs to be sent downstream?
				if (curEvent.data != nil) {
					var captureData = self.datas[curEvent.fh]
					if (captureData != nil) {
						captureData!.append(curEvent.data!)
						self.datas[curEvent.fh] = captureData
					} else {
						self.datas[curEvent.fh] = curEvent.data
					}
				}
			}
		}
	}
	
	func register(readers:[ReadableConfiguration], writer:WritableConfiguration) {
		var readersToRegister = [InboundChannelState]()
		self.internalSync.sync {
			self.groups[writer.fh] = writer.group
			for (_, curReaderConfig) in readers.enumerated() {
				let newReader = InboundChannelState(fh:curReaderConfig.fh, mode:curReaderConfig.parseMode, dataHandler:curReaderConfig.handler)
				readersToRegister.append(newReader)
			}
		}
	}
	
	//process loop
	func _mainLoop() {
		while true {
			//wait for datas or closures to hit so that they can be retrieved in this loop
			self.loopGroup.wait()
			
			let curEvents = self.extractEvents()
			
			curEvents.master.explode(using: { (_, curHandle) in
				let isClosed = curEvents.closed.contains(curHandle)
				let captureData = curEvents.datas[curHandle]
				if (captureData != nil) {
					curEvents.readers[curHandle]!.capture(data:captureData!, terminate:isClosed)
				}
				if (isClosed) {
					let captureGroup = curEvents.groups[curHandle]
					if (captureGroup != nil) {
						captureGroup!.removeHandle(fh:curHandle)
					}
				}
			})
		}
	}

}