import Foundation

class ChannelManager {
	let internalSync = DispatchQueue(label:"com.swiftslash.file-handle-capture.instance.sync", target:process_master_queue)
	
	var states = [Int32:EventMode]()
	var readers = [Int32:InboundChannelState]()
	var writers = [Int32:OutboundChannelState]()
	var groups = [Int32:TerminationGroup]()
	
	var loopEnabled = false
	let loopGroup = DispatchGroup()
	
	weak var eventTrigger:EventTrigger?
	
	init() {
		loopGroup.enter()
	}
	
	//this is a function that ensures that the main loop stops running if there are no shell instances active
	fileprivate func _adjustLoopGroupState() {
		if (self.states.count == 0 && loopEnabled == true) {
			loopEnabled = false
			loopGroup.enter() //pause the loop by entering the loop group
		} else if (self.states.count > 0 && loopEnabled == false) {
			loopEnabled = true
			loopGroup.leave() //resume the loop by leaving the loop group
		}
	}
	
	//extract the reading events from a current process state
	fileprivate struct ExtractionPackage {
		let states:[Int32:EventMode]
		let readers:[Int32:InboundChannelState]
		let writers:[Int32:OutboundChannelState]
	}
	fileprivate enum HandleLoopResult {
		case activeReader(Int32)
		case clearReader(Int32)
		case clearWriter(Int32)
	}
	fileprivate func extractEvents(actions:[HandleLoopResult]) -> ExtractionPackage {
		return self.internalSync.sync {
			//insert reading events for the file handles that are still active from the last run loop iteration
			for (_, curAction) in actions.enumerated() {
				switch curAction {
					case let .activeReader(thisFH):
						let checkValue = self.states[thisFH]
						if (checkValue != .readingClosed) {
							_ = self.states.updateValue(.readableEvent, forKey:thisFH)
						}
					case let .clearReader(thisFH):
						_ = self.readers.removeValue(forKey:thisFH)
						_ = self.states.removeValue(forKey:thisFH)
						let checkGroups = self.groups.removeValue(forKey:thisFH)
						if (checkGroups != nil) {
							checkGroups!.removeHandle(fh:thisFH)
						}
						if (self.eventTrigger != nil) {
							try? self.eventTrigger!.deregister(reader:thisFH)
						}
						thisFH.closeFileHandle()
						
					case let .clearWriter(thisFH):
						_ = self.writers.removeValue(forKey:thisFH)
						_ = self.states.removeValue(forKey:thisFH)
						let checkGroups = self.groups.removeValue(forKey:thisFH)
						if (checkGroups != nil) {
							checkGroups!.removeHandle(fh:thisFH)
						}
						if (self.eventTrigger != nil) {
							try? self.eventTrigger!.deregister(writer:thisFH)
						}
						thisFH.closeFileHandle()
				}
			}
			
			//capture the events and states as they currently exist in the synchrony state
			let captureStates = self.states
			let captureReaders = self.readers
			let captureWriters = self.writers
			
			//clear the events for all but the final readable
			self._adjustLoopGroupState()
			self.states.removeAll(keepingCapacity:true)
			
			return ExtractionPackage(states:captureStates, readers:captureReaders, writers:captureWriters)
		}
	}
	
	func _mainLoop() {
		//this stores the file handles that are active for reading and need to be included in the next iteration
		var postLoopResults = [HandleLoopResult]()
		while true {
			//sleep the run loop if there are no active file handles to process
			if (postLoopResults.count == 0) {
				loopGroup.wait()
			}			
			
			//extract the current file handle events 
			let curEvents = self.extractEvents(actions:postLoopResults)
			postLoopResults.removeAll(keepingCapacity:true)
			
			//process the states and compile a list of HandleLoopResults to incorporate into the next synchronization phase
			curEvents.states.explode(using: { (_, kv) -> ChannelManager.HandleLoopResult? in
				var returnValue:HandleLoopResult? = nil
				switch (kv.value) {
					case .readableEvent:
						//find the object that we want to read with
						let inboundConfig = curEvents.readers[kv.key]
						if (inboundConfig != nil) {							
							//tell the object to capture data - the object will return if the handle is blocked
							let captureResult = inboundConfig!.captureData(terminate:false)
							if (captureResult) {
								//include this file handle in the return value so that it can be safely merged into the clearReaders variable 
								returnValue = .activeReader(kv.key)
							}
						}
						
					case .writableEvent:
						let outboundConfig = curEvents.writers[kv.key]
						if (outboundConfig != nil) {
							outboundConfig!.channelWriteableEvent()
						}
						
					case .readingClosed:
						let inboundConfig = curEvents.readers[kv.key]
						if (inboundConfig != nil) {
							_ = inboundConfig!.captureData(terminate:true)
							returnValue = .clearReader(kv.key)
						}
					
					case .writingClosed:
						let outboundConfig = curEvents.writers[kv.key]
						if (outboundConfig != nil) {
							returnValue = .clearWriter(kv.key)
						}
						
				}
				return returnValue
			}, merge: { (_, curResult) in
				postLoopResults.append(curResult)
			})
		}
	}
		
	func register(readers:[ReadableConfiguration], writer:WritableConfiguration) -> OutboundChannelState {
		return self.internalSync.sync {
			for (_, curReadable) in readers.enumerated() {
				let newConfig = InboundChannelState(fh:curReadable.fh, mode:curReadable.parseMode, dataHandler:curReadable.handler)
				_ = self.readers.updateValue(newConfig, forKey:curReadable.fh)
				_ = self.groups.updateValue(curReadable.group, forKey:curReadable.fh)
			}
			let newWriter = OutboundChannelState(fh:writer.fh)
			_ = self.writers.updateValue(newWriter, forKey:writer.fh)
			_ = self.groups.updateValue(writer.group, forKey:writer.fh)
			return newWriter
		}
	}
		
	//batch intake new file handles
	func assignNewEvents(_ fhEvents:[Int32:EventMode]) {
		self.internalSync.sync { [fhEvents] in
			for (_, kv) in fhEvents.enumerated() {
				_ = self.states.updateValue(kv.value, forKey:kv.key)
			}
			self._adjustLoopGroupState()
		}
	}
					
}