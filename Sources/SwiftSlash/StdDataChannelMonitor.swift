import Foundation
import Cepoll

internal class StdDataChannelMonitor {
	typealias DataIntakeHandler = (Data) -> Void
	typealias GenericHandler = () -> Void
	
	static let dataCaptureQueue = DispatchQueue(label:"com.swiftslash.global.data-channel-monitor.reading", attributes:[.concurrent], target:swiftslashCaptainQueue)
	static let dataCallbackQueue = DispatchQueue(label:"com.swiftslash.global.data-channel-monitor.writing", attributes:[.concurrent], target:swiftslashCaptainQueue)
	
	class IncomingChannel:Equatable {
		enum TriggerMode {
			case lineBreakParsed;
			case lineBreakUnparsed;
			case immediate;
		}
		
		let fh:Int32
		
		var epollStructure = epoll_event()
		let mainQueue = DispatchQueue(label:"com.swiftslash.instance.data-channel-monitor.reading", target:dataCaptureQueue)
		let callbackQueue = DispatchQueue(label:"com.swiftslash.instance.data-channel-monitor.callback", target:dataCallbackQueue)
		
		let runningGroup = DispatchGroup()
		var dataBuffer = Data()
	
		let triggerMode:TriggerMode
		let dataHandler:DataIntakeHandler
		let terminationHandler:GenericHandler
	
		init(fh:Int32, triggerMode:TriggerMode, dataHandler:@escaping(DataIntakeHandler), terminationHandler:@escaping(GenericHandler)) {
			self.fh = fh
			
			self.epollStructure.data.fd = fh
			self.epollStructure.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
			
			self.triggerMode = triggerMode
		
			self.dataHandler = dataHandler
			self.terminationHandler = terminationHandler
		}
		
		//this is called by the owning function
		func readIncomingData() {
			mainQueue.async { [weak self] in 
				guard let self = self else {
					return
				}
				self.runningGroup.enter()
				self.fireReadEvent()
				self.runningGroup.leave()
			}
		}
	
		//this main loop is called as soon as 
		private func fireReadEvent(closing:Bool) {
			//capture the data from this file handle
			do {
				while let capturedData = try self.fh.readFileHandle() {
					self.dataBuffer.append(capturedData)
				}
			} catch FileHandleError.error_pipe {
			} catch FileHandleError.error_again, FileHandleError.error_wouldblock {
			} catch let error {
				print("IO ERROR: \(error)")
			}
			
			//fire the data handler based on our triggering mode
			switch triggerMode {
				case .lineBreakParsed:
				case .lineBreakUnparsed:
					//parse the data buffer for lines
					var shouldParse = dataBuffer.withUnsafeBytes { unsafeBuffer in
						var i = 0
						while (i < dataBuffer.count) {
							if (unsafeBuffer[i] == 10 || unsafeBuffer[i] == 13) {
								return true
							}
							i = i + 1;
						}
						return false
					}
					if closing == true { 
						shouldParse = true
					}
					//trigger the data handler for the lines we have picked up.
					switch shouldParse {
						case true:
							let lineParse = dataBuffer.cutLines(flush:closing)
							if lineParse.lines != nil {
								self.callbackQueue.async { [weak self, pl = lineParse.lines] in
									guard let self = self else {
										return
									}
									for (_, curLine) in pl!.enumerated() {
										dataHandler(curLine)
									}
								}
								
							}
							if closing == false {
								let cutCapture = dataBuffer[lineParse.cut..<dataBuffer.endIndex]
								dataBuffer.removeAll(keepingCapacity:true)
								dataBuffer.append(cutCapture)
							} else {
								dataBuffer.removeAll(keepingCapacity:false)
							}
							
						case false:
							break;
					}
				case .immediate:
					//immediate data handling mode is far simpler
					dataHandler(self.dataBuffer)
					dataBuffer.removeAll(keepingCapacity:true)
			}
		}
	
		static func == (lhs:IncomingChannel, rhs:IncomingChannel) -> Bool {
			if lhs.fh == rhs.fh {
				return true
			} else {
				return false
			}
		}
	
		func hash(into hasher:inout Hasher) {
			hasher.combine(fh)
		}
	}
	
	struct OutgoingHandler:Equatable {
	//	let fh:Int32
	//
	//	let main:DispatchQueue = DispatchQueue(label:".com.swiftslash.data-channel-monitor.")
	}

	let epoll = epoll_create1(0);
	
	let mainQueue = DispatchQueue(label:"com.swiftslash.data-channel-monitor.main.sync", target:swiftslashCaptainQueue)
	var mainLoopLaunched = false
	
	//`EventMode` is used by the main loop of this object
	private enum EventMode {
		case readableEvent
		case writableEvent
		case readingClosed
		case writingClosed
	}
	//When events are received from the epoll loop, the workloads to dispatch concurrent workloads into this queue
	let events = DispatchQueue(label:"com.swiftslash.data-channel-monitor.events", attributes:[.concurrent], target:swiftslashCaptainQueue)

	let internalSync = DispatchQueue(label:"com.swiftslash.data-channel-monitor.global-instance.sync", target:swiftslashCaptainQueue)
	var currentAllocationSize = 32
	var targetAllocationSize = 32
	var currentAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:32)
	var readers = [Int32:IncomingChannel]()
	var writers = [Int32:OutgoingHandler]()

	private func adjustTargetAllocations() {
		if (((self.readers.count + self.writers.count) * 2) > targetAllocationSize) {
			targetAllocationSize = currentAllocationSize * 2
		} else if (Int(ceil(Double(targetAllocationSize)*0.20)) > (self.readers.count + self.writers.count)) {
			targetAllocationSize = Int(ceil(Double(currentAllocationSize)*0.5))
		}
		
		if targetAllocationSize < 32 {
			targetAllocationSize = 32
		}
	}
	
	func registerInboundDataChannel(fh:Int32, mode:IncomingChannel.TriggerMode, dataHandler:@escaping(DataIntakeHandler), terminationHandler:@escaping(GenericHandler)) throws {
		internalSync.async { [weak self] in
			guard let self = self else {
				return
			}
			self.readers[fh] = IncomingChannel(fh:fh, triggerMode:mode, dataHandler:dataHandler, terminationHandler:terminationHandler)
			self.adjustTargetAllocations()
			if (self.mainLoopLaunched == false) {
				//launch the main loop if it is not already running
				self.mainLoopLaunched = true
				self.mainQueue.async { [weak self] in
					guard let self = self else {
						return
					}
					self.mainLoop()
				}
			}
		}
	}

	func mainLoop() {
		var handleEvents = [Int32:EventMode]()
		while true {
			let (readAllocation, allocationSize) = internalSync.sync { () -> (UnsafeMutablePointer<epoll_event>, Int) in
				for (_, curEvent) in handleEvents.enumerated() {
					switch curEvent.value {
						case .readableEvent:
							if readers[curEvent.key] != nil {
								readers[curEvent.key]!.readIncomingData() 
							}
						case .writableEvent:
						
						case .readingClosed:
						
						case .writingClosed:
							
					}
				}
				if (targetAllocationSize != currentAllocationSize {
					currentAllocation.deallocate()
					currentAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:32)
					currentAllocationSize = targetAllocationSize
					return (currentAllocation, currentAllocationSize)
				} else {
					return (currentAllocation, currentAllocationSize)
				}
			}
			
			let pollResult = epoll_wait(epoll, readAllocation, allocationSize, -1)
			if pollResult == -1 && errno == EINTR {
				//there was an error...sleep and try again
				nanosleep(100000000) //0.1 seconds
			} else {
				//there was no error...run it
				var i:Int32 = 0
				while (i < pollResult) {
					let currentEvent = readAllocation[i]
					if (currentEvent.events & UInt32(EPOLLIN.rawValue) != 0) {
						//read data available
					} else if (currentEvent.events & UInt32(POLLHUP.rawValue) != 0) {
						//reading handle closed
					} else if (currentEvent.events & UInt32(EPOLLOUT.rawValue) != 0) {
						//writing available
					} else if (currentEvent.events & UInt32(EPOLLERR.rawValue) != 0) {
					
					}
				
					i = i + 1;
				}
			}
			
		}
	}
}