import Foundation
import Cepoll

protocol FileHandleOwner {
	func handleEndedLifecycle(_ fh:Int32)
}

internal class StdDataChannelMonitor:FIleHandleOwner {
	
	typealias InboundDataHandler = (Data) -> Void
	typealias OutboundDataHandler = () -> Data
	typealias DataChannelTerminationHander = () -> Void
	
	static let dataCaptureQueue = DispatchQueue(label:"com.swiftslash.global.data-channel-monitor.reading", attributes:[.concurrent], target:swiftslashCaptainQueue)
	static let dataBroadcastQueue = DispatchQueue(label:"com.swiftslash.global.data-channel-monitor.writing", attributes:[.concurrent], target:swiftslashCaptainQueue)
	
	private class IncomingDataChannel {
		enum TriggerMode {
			case lineBreaks
			case immediate
		}
		
		//defined on initialization
		private let inboundHandler:InboundDataHandler
		private let terminationHandler:DataChannelTerminationHandler
		let fh:Int32
		let triggerMode:TriggerMode
		let epollStructure:epoll_event
		weak let manager:FileHandleOwner

		private var asyncCallbackScheduled = false
		private var callbackFires = [Data]()
		private var dataBuffer = Data()
		
		//workload queues
		private let internalSync = DispatchQueue(label:"com.swiftslash.instance.incoming-data-channel.sync", target:dataCaptureQueue)
		private let captureQueue = DispatchQueue(label:"com.swiftslash.instance.incoming-data-channel.capture", target:dataCaptureQueue)
		private let callbackQueue = DispatchQueue(label:"com.swiftslash.instance.incoming-data-channel.callback", target:dataCaptureQueue)
		private let flightGroup = DispatchGroup();
		
		init(fh:Int32, triggerMode:TriggerMode, dataHandler:@escaping(InboundDataHandler), terminationHandler:@escaping(OutboundDataHandler), manager:FileHandleOwner) {
			self.fh = fh
			
			var buildEpoll = epoll_event()
			buildEpoll.data.fd = fh
			buildEpoll.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
			self.epollStructure = buildEpoll
			
			self.inboundHandler = dataHandler
			self.terminationHandler = terminationHandler
			
			self.manager = manager
		}
		
		func initiateDataCaptureIteration(terminate:Bool) {
			self.flightGroup.enter();
			captureQueue.async { [weak self] in
				guard let self = self else {
					return
				}
				defer {
					self.flightGroup.leave()
				}
				//capture the data
				var didReadTerminate = false
				do {
					while let captureData = try self.fh.readFileHandle() {
						self.dataBuffer.append(captureData)
					}
				} catch FileHandleError.error_again, FileHandleError.error_wouldblock {
					//do nothing
				} catch FileHandleError.error_pipe {
					didReadTerminate = true
				} catch let error {
					print("IO ERROR: \(error)")
				}
				
				//parse the data based on the triggering mode
				switch triggerMode {
					case .lineBreaks:
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
						
						switch shouldParse {
							case true:
								let parsedLines = dataBuffer.cutLines(flush:terminate)
								if parsedLines.lines != nil && parsedLines.lines!.count != 0 {
									internalSync.sync {
										dataBuffer = dataBuffer.suffix(from:parsedLines.cut)
										callbackFires.append(contentsOf:parsedLines.lines!) //the parsed lines need to be fired against the data handler
										if asyncCallbackScheduled == false {
											asyncCallbackScheduled = true
											self.scheduleAsyncCallback()
										}
									}
								}
							case false:
								break;
						}
					case .immediate:
						internalSync.sync {
							callbackFires.append(dataBuffer)
							self.dataBuffer.removeAll(keepingCapacity:true)
							self.scheduleAsyncCallback()
						}
				}
			}
		}
		
		func scheduleAsyncCallback() {
			self.flightGroup.enter()
			self.callbackQueue.async { [weak self] in
				guard let self = self else {
					return
				}
				defer {
					self.flightGroup.leave()
				}
				
				//capture the data that needs to fire against the incoming data handler
				var dataForCallback = internalSync.sync {
					defer {
						self.callbackFires.removeAll(keepingCapacity:true)
					}
					return self.callbackFires
				}
				
				//if trigger mode is immediate (unparsed), collapse the callback fires into a single fire with all the data appended
				if triggerMode == .immediate {
					var singleData = Data()
					for (_, curData) in dataForCallback.enumerated() {
						singleData.append(curData)
					}
					dataForCallback = [singleData]
				}
				
				//fire the intake handler
				for (_, curCallbackChunk) in dataForCallback.enumerated() {
					self.inboundHandler(curCallbackChunk)
				}
			}
		}
		
		func scheduleAsyncTermination() {
			self.flightGroup.enter()
			self.callbackQueue.async { [weak self] in
				
			}
		}
	}
	
	class OutgoingDataChannel:Equatable, Hashable {
		let fh:Int32
		
		let internalSync = DispatchQueue(label:"com.swiftslash.instance.outgoing-data-queue.sync")
		let writingQueue = DispatchQueue(label:"com.swiftslash.instance.outgoing-data-queue.write")
		let flightGroup = DispatchGroup()
		
		var dataWriteScheduled = false
		var handleIsWritable = false
		var remainingData = Data()
		
		let outboundHandler:OutboundDataHandler
		let terminationHandler:TerminationHandler
		
		weak let manager:FileHandleOwner
		
		init(fh:Int32, dataHandler:OutboundDataHandler, terminationHandler:TerminationHandler, manager:FileHandleOwner) {
			self.fh = fh
			self.outboundHandler = dataHandler
			self.terminationHandler = terminationHandler
			self.manager = manager
		}
		
		func scheduleDataForWriting(_ inputData:Data) {
			
		}
		
		func handleIsAvailableForWriting(_ )
	}

	let epoll = epoll_create1(0);
	
	let mainQueue = DispatchQueue(label:"com.swiftslash.data-channel-monitor.main.sync", target:swiftslashCaptainQueue)
	var mainLoopLaunched = false
	
	//When events are received from the epoll loop, the workloads to dispatch concurrent workloads into this queue
	let events = DispatchQueue(label:"com.swiftslash.data-channel-monitor.events", attributes:[.concurrent], target:swiftslashCaptainQueue)

	let internalSync = DispatchQueue(label:"com.swiftslash.data-channel-monitor.global-instance.sync", target:swiftslashCaptainQueue)
	var currentAllocationSize = 32
	var targetAllocationSize = 32
	var currentAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:32)
	var readers = [Int32:IncomingDataChannel]()
	var writers = [Int32:OutgoingDataHandler]()

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
	
	func registerInboundDataChannel(fh:Int32, mode:IncomingDataChannel.TriggerMode, dataHandler:@escaping(DataIntakeHandler), terminationHandler:@escaping(GenericHandler)) throws {
		internalSync.async { [weak self] in
				return
			}
			self.readers[fh] = IncomingDataChannel(fh:fh, triggerMode:mode, dataHandler:dataHandler, terminationHandler:terminationHandler)
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
	
	func scheduleOutboundWrite(fh:Int32, dataIntake:@escaping(DataWritingHandler)

	func mainLoop() {
	
		var handleEvents = [Int32:EventMode]()
		while true {
			/*
				THIS IS THE MAIN LOOP: let us discuss what this loop is doing
				This main loop can be broken down into two primary phases
				=============================================================
				Phase 1: (synchronized with `internalSync` queue)
					Phase 1 is internally synchronized with the class's primary body of instance variables
					During this phase, any pending handle events that have been written to the `handleEvents` variable passed are passed to and processed asynchronously by the individual `IncomingDataChannel` objects. During this phase, these asynchronous events are triggered and fired
					During this phase, the current allocation size of the `epoll_event` buffer is resized to the target allocation size.
					The internally synchronized block is responsible for returning two variables:
						1. The pointer to the current allocated buffer that can be passed to `epoll_wait() in the next phase
						2. The size of the currently allocated buffer. this is also passed to `epoll_wait()` in the next phase
				Phase 2: (unsynchronized)
					Phase to consists of calling `epoll_wait()` and parsing the results of the call
			*/
			let (readAllocation, allocationSize) = internalSync.sync { () -> (UnsafeMutablePointer<epoll_event>, Int) in
				for (_, curEvent) in handleEvents.enumerated() {
					switch curEvent.value {
						case .readableEvent:
							if readers[curEvent.key] != nil {
								readers[curEvent.key]!.readIncomingData(flushMode:false) 
							} else {
								print("`epoll_wait()` received an event for a file handle not stored in this instance.")
							}
						case .writableEvent:
							break;	//TODO
							if writers[curEvent.key] != nil {
								writers[curEvent.key]!.write
							}
						case .readingClosed:
							if readers[curEvent.key] != nil {
								readers[curEvent.key]!.readIncomingData(flushMode:true)
							} else {
								print("`epoll_wait()` received an event for a file handle not stored in this instance.")
							}
						case .writingClosed:
							break; //TODO
							
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
						handleEvents[currentEvent.data.fd] = .readableEvent
					} else if (currentEvent.events & UInt32(POLLHUP.rawValue) != 0) {
						//reading handle closed
						handleEvents[currentEvent.data.fd] = .readingClosed
					} else if (currentEvent.events & UInt32(EPOLLOUT.rawValue) != 0) {
						//writing available
						handleEvents[currentEvent.data.fd] = .writableEvent
					} else if (currentEvent.events & UInt32(EPOLLERR.rawValue) != 0) {
						//writing handle closed
						handleEvents[currentEvent.data.fd] = .writingClosed
					}
				
					i = i + 1;
				}
			}
			
		}
	}
}