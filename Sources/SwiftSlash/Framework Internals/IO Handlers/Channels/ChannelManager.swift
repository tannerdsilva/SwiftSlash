import Foundation
import Glibc

class ChannelManager {
	let internalSync = DispatchQueue(label:"com.swiftslash.file-handle-capture.instance.sync", target:process_master_queue)
	
	var states = [Int32:EventMode]() //states for readers and writers
	var sizes = [Int32:Int32]() //for reading
	var writers = [Int32:OutboundChannelState]() //for writing
	
	var loopEnabled = false
	let loopGroup = DispatchGroup()
	
	weak var eventTrigger:EventTrigger?
	weak var downstreamHandler:DownstreamHandler?
	
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
	fileprivate struct ExtractionPackage:Equatable, Hashable {
		let states:[Int32:EventMode] //states of readers and writers
		let sizes:[Int32:Int32] //for reading
		let writers:[Int32:OutboundChannelState] //for writing
		var downstream:[CapturedHandleEvent] //generated events that go downstream to the next handler
		
		static func == (lhs:ExtractionPackage, rhs:ExtractionPackage) -> Bool {
			return (lhs.states == rhs.states) && (lhs.sizes == rhs.sizes) && (lhs.writers == rhs.writers) && (lhs.downstream == rhs.downstream)
		}
		func hash(into hasher:inout Hasher) {
			hasher.combine(self.states)
			hasher.combine(self.sizes)
			hasher.combine(self.writers)
			hasher.combine(self.downstream)
		}
	}
	internal struct CapturedHandleEvent:Equatable, Hashable {
		let fh:Int32
		let closed:Bool
		let time:timeval
		let data:Data?
		
		init(fh:Int32, closed:Bool, data:Data?) {
			self.fh = fh
			self.closed = closed
			self.time = CurrentProcessState.getCurrentSystemTime()
			self.data = data
		}
		
		//MARK: Equatable
		static func == (lhs:CapturedHandleEvent, rhs:CapturedHandleEvent) -> Bool {
			if (lhs.fh == rhs.fh) && (lhs.closed == rhs.closed) && (lhs.time == rhs.time) && (lhs.data == rhs.data) {
				return true
			} else {
				return false
			}
		}
		func hash(into hasher:inout Hasher) {
			hasher.combine(self.fh)
			hasher.combine(self.closed)
//			hasher.combine(self.time)
			if (self.data != nil) {
				hasher.combine(self.data!)
			}
		}
	}
	fileprivate func extractEvents(actions:[EventResult]) -> ExtractionPackage {
		return self.internalSync.sync {
			var buildDownstream = [CapturedHandleEvent]()
			//insert reading events for the file handles that are still active from the last run loop iteration
			for (_, curAction) in actions.enumerated() {
				switch curAction.direction {
					case .readingInbound:
						if (curAction.isClosed) {
							_ = self.sizes.removeValue(forKey:curAction.fh)
						} else {
							if (curAction.sizeDelta != 0) {
								let currentSize = self.sizes[curAction.fh]!
								self.sizes[curAction.fh] = currentSize + curAction.sizeDelta
							}			
							if (curAction.isActive) {
								_ = self.states.updateValue(.readableEvent, forKey:curAction.fh)
							}
						}
						if (curAction.capturedData != nil && curAction.capturedData!.count > 0) || (curAction.isClosed == true) {
							buildDownstream.append(CapturedHandleEvent(fh:curAction.fh, closed:curAction.isClosed, data:curAction.capturedData))
						}
					case .writingOutbound:
						if (curAction.isClosed) {
							_ = self.writers.removeValue(forKey:curAction.fh)
							buildDownstream.append(CapturedHandleEvent(fh:curAction.fh, closed:true, data:nil))
						}
				}
			}
			
			//capture the events and states as they currently exist in the synchrony state
			let captureStates = self.states
			let captureWriters = self.writers
			let captureSizes = self.sizes
			
			//clear the events for all but the final readable
			self._adjustLoopGroupState()
			self.states.removeAll(keepingCapacity:true)
			
			return ExtractionPackage(states:captureStates, sizes:captureSizes, writers:captureWriters, downstream:buildDownstream)
		}
	}
	
	fileprivate struct EventResult:Equatable, Hashable {
		fileprivate enum Direction:UInt8 {
			case readingInbound = 0
			case writingOutbound = 1
		}
		let direction:Direction
		let fh:Int32
		let sizeDelta:Int32
		let isActive:Bool
		let isClosed:Bool
		let capturedData:Data?
		
		init(_ direction:Direction, fh:Int32, sizeDelta:Int32, isActive:Bool, isClosed:Bool, capturedData:Data?) {
			self.direction = direction
			self.fh = fh
			self.sizeDelta = sizeDelta
			self.isActive = isActive
			self.isClosed = isClosed
			self.capturedData = capturedData
		}
		
		static func == (lhs:EventResult, rhs:EventResult) -> Bool {
			return (lhs.direction == rhs.direction) && (lhs.fh == rhs.fh) && (lhs.sizeDelta == rhs.sizeDelta) && (lhs.isActive == rhs.isActive) && (lhs.isClosed == rhs.isClosed) && (lhs.capturedData == rhs.capturedData)
		}
		
		func hash(into hasher:inout Hasher) {
			hasher.combine(self.direction)
			hasher.combine(self.fh)
			hasher.combine(self.sizeDelta)
			hasher.combine(self.isActive)
			hasher.combine(self.isClosed)
			if (self.capturedData != nil) {
				hasher.combine(self.capturedData!)
			}
		}
	}
	
	func _mainLoop() {
		//this stores the file handles that are active for reading and need to be included in the next iteration
		var postLoopResults = [EventResult]()
		var lastIteration = Date()
		while true {
			//sleep the run loop if there are no active file handles to process
			if (postLoopResults.count == 0) {
				loopGroup.wait()
			}			
			
			//extract the current file handle events 
			let curEvents = self.extractEvents(actions:postLoopResults)
			postLoopResults.removeAll(keepingCapacity:true)
			
			if (self.downstreamHandler != nil) {
				
			}
			//process the states and compile a list of HandleLoopResults to incorporate into the next synchronization phase
			curEvents.states.explode(using: { (_, kv) -> EventResult? in
				switch (kv.value) {
					case .readableEvent:
						//capture the data from the file handle
						var isReadable = true
						let readSize = self.sizes[kv.key]!
						var capturedData:Data
						do {
							capturedData = try kv.key.readFileHandle(size:Int(readSize))
						} catch FileHandleError.error_again {
							isReadable = false
							capturedData = Data()
						} catch FileHandleError.error_wouldblock {
							isReadable = false
							capturedData = Data()
						} catch FileHandleError.error_pipe {
							print("PIPE ERROR")
							capturedData = Data()
						} catch _ {
							capturedData = Data()
						}
						
						//return the result
						let sizeDelta = (capturedData.count*2 > readSize) ? readSize : 0
						if (sizeDelta > 0) {
							print("info: adjusting size delta for \(kv.key) by \(sizeDelta)")
						}
						return EventResult(.readingInbound, fh:kv.key, sizeDelta:sizeDelta, isActive:isReadable, isClosed:false, capturedData:capturedData)
						
					case .writableEvent:
						curEvents.writers[kv.key]!.channelWriteableEvent()
						return nil
						
					case .readingClosed:
						//capture the data from the file handle
						let readSize = curEvents.sizes[kv.key]!
						var capturedData = Data(capacity:Int(readSize))
						do {
							repeat {
								try capturedData.append(kv.key.readFileHandle(size:Int(readSize)))
							} while true
						} catch _ {
						}
						
						if (self.eventTrigger != nil) {
							try? self.eventTrigger!.deregister(reader:kv.key)
						}
						kv.key.closeFileHandle()
						return EventResult(.readingInbound, fh:kv.key, sizeDelta:0, isActive:false, isClosed:true, capturedData:capturedData)
					
					case .writingClosed:
						if (self.eventTrigger != nil) {
							try? self.eventTrigger!.deregister(writer:kv.key)
						}
						curEvents.writers[kv.key]!.closeFileHandle()
						return EventResult(.writingOutbound, fh:kv.key, sizeDelta:0, isActive:false, isClosed:true, capturedData:nil)
				}
			}, merge: { (_, curResult) in
				postLoopResults.append(curResult)
			})
			print("------------- \(lastIteration.timeIntervalSinceNow) -------------")
		}
	}
		
	func register(writer:WritableConfiguration) -> OutboundChannelState {
		return self.internalSync.sync {
			let newWriter = OutboundChannelState(fh:writer.fh)
			_ = self.writers.updateValue(newWriter, forKey:writer.fh)
			return newWriter
		}
	}
		
	//batch intake new file handles
	func assignNewEvents(_ fhEvents:[Int32:EventMode]) {
		self.internalSync.sync { [fhEvents] in
			for (_, kv) in fhEvents.enumerated() {
				if (kv.value == .readableEvent) && (self.sizes[kv.key] == nil) {
					_ = self.sizes.updateValue(PIPE_BUF, forKey:kv.key)
				}
				_ = self.states.updateValue(kv.value, forKey:kv.key)
			}
			self._adjustLoopGroupState()
		}
	}
}