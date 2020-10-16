import Foundation
import Cepoll

//this object breaks an incoming bytestream into lines based on the configured `DataParseMode`
internal struct BufferedLineParser {
	internal var type:DataParseMode
	
	fileprivate var currentLine = Data()
	fileprivate var pendingLines = [Data]()
	
	init(mode:DataParseMode) {
		self.type = mode
	}
	
	mutating func intake(_ dataToIntake:Data) -> Bool {
		var didFind = false
		var crLast = false
		if (self.type == .immediate) {
			pendingLines.append(dataToIntake)
			return true
		}
		dataToIntake.withUnsafeBytes { unsafeBytes in
			var i = 0
			while (i < dataToIntake.count) {
				defer {
					i = i + 1
				}
				let curByte = unsafeBytes[i]
				switch type {
					case .cr:
						if (curByte == 13) {
							pendingLines.append(currentLine)
							currentLine.removeAll(keepingCapacity:true)
							didFind = true
						} else {
							currentLine.append(curByte)
						}
					case .lf:
						if (curByte == 10) {
							pendingLines.append(currentLine)
							currentLine.removeAll(keepingCapacity:true)
							didFind = true
						} else {
							currentLine.append(curByte)
						}
					case .crlf:
						if (crLast == true && curByte == 10) {
							crLast = false
							pendingLines.append(currentLine)
							currentLine.removeAll(keepingCapacity:true)
							didFind = true
						} else if (crLast == false && curByte == 13) {
							crLast = true
						} else {
							if (crLast == true) {
								currentLine.append(13)
							}
							crLast = false
							currentLine.append(curByte)
						}
					default:
						break
				}
			}
		}
		return didFind
	}
	
	mutating func flushLines() -> [Data] {
		let pendingLinesCopy = self.pendingLines
		self.pendingLines.removeAll()
		return pendingLinesCopy
	}
	
	mutating func flushFinal() -> [Data] {
		let currentLineCopy = self.currentLine
		self.currentLine.removeAll(keepingCapacity:false)
		var returnLines = self.pendingLines
		self.pendingLines.removeAll()
		if (currentLineCopy.count > 0) {
			returnLines.append(self.currentLine)
		}
		return returnLines
	}
}

//this class handles concurrent IO for all processes globally
internal class DataChannelMonitor {
	enum DataChannelMonitorError:Error {
		case invalidFileHandle
		case epollError
	}
	static let global = DataChannelMonitor()
	
	typealias InboundDataHandler = (Data) -> Void
	typealias OutboundDataHandler = () -> Data
	typealias DataChannelTerminationHander = () -> Void
	
	fileprivate static let dataCaptureQueue = DispatchQueue(label:"com.swiftslash.global.data-channel-monitor.reading", attributes:[.concurrent], target:process_master_queue)
	fileprivate static let dataBroadcastQueue = DispatchQueue(label:"com.swiftslash.global.data-channel-monitor.writing", attributes:[.concurrent], target:process_master_queue)
	
	internal class IncomingDataChannel {
		//constant variables that are defined on initialization
		private let inboundHandler:InboundDataHandler
		private let terminationHandler:DataChannelMonitor.DataChannelTerminationHander
		let fh:Int32
		var triggerMode:DataParseMode {
			get {
				return self.captureQueue.sync {
					return self.lineParser.type
				}
			}
			set {
				self.captureQueue.sync { [newValue] in
					self.lineParser.type = newValue
				}
			}
		}
		let epollStructure:epoll_event
		weak var manager:DataChannelMonitor?
		
		//workload queues
		private let captureQueue = DispatchQueue(label:"com.swiftslash.instance.incoming-data-channel.capture", target:dataCaptureQueue)
		private let flightGroup = DispatchGroup();
		
		init(fh:Int32, triggerMode:DataParseMode, dataHandler:@escaping(InboundDataHandler), terminationHandler:@escaping(DataChannelTerminationHander), manager:DataChannelMonitor) {
			self.fh = fh
			
			var buildEpoll = epoll_event()
			buildEpoll.data.fd = fh
			buildEpoll.events = UInt32(EPOLLIN.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
			self.epollStructure = buildEpoll
			
			self.inboundHandler = dataHandler
			self.terminationHandler = terminationHandler
			
			self.manager = manager
			self.lineParser = BufferedLineParser(mode:triggerMode)
		}
		
		//FileHandleOwner will call this function when the relevant file handle has become available for reading
		private var lineParser:BufferedLineParser	//used exclusively in this function
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
				do {
					while true {
						let capturedData = try self.fh.readFileHandle()
						switch self.lineParser.type {
							case .immediate:
								self.inboundHandler(capturedData)
							default:
								let hasNewLines = self.lineParser.intake(capturedData)
								if (hasNewLines == true && terminate == false) {
									for (_, curItem) in self.lineParser.flushLines().enumerated() {
										self.inboundHandler(curItem) 
									}
								}
						}
						
					}
				} catch FileHandleError.error_again {
				} catch FileHandleError.error_wouldblock {
				} catch FileHandleError.error_pipe {
				} catch let error {
					print("[SWIFTSLASH] IO ERROR: \(error)")
				}

				if terminate == true {
					//in linebreak mode there might be some callback fires that need to be called....
					if (self.lineParser.type != .immediate) {
						for (_, curItem) in self.lineParser.flushFinal().enumerated() {
							self.inboundHandler(curItem) 
						}
					}
					//fire the termination handler
					self.terminationHandler()
					//notify the manager that we're at the end of lifecycle
					self.manager?.handleEndedLifecycle(reader:self.fh)
				}
			}
		}
				
		deinit {
			self.flightGroup.wait()
		}
	}
	
	internal class OutgoingDataChannel:Equatable, Hashable {
		let fh:Int32
		
		let internalSync = DispatchQueue(label:"com.swiftslash.instance.outgoing-data-queue.sync", target:dataBroadcastQueue)
		let writingQueue = DispatchQueue(label:"com.swiftslash.instance.outgoing-data-queue.write", target:dataBroadcastQueue)
		let flightGroup = DispatchGroup()
		
		var dataWriteScheduled = false
		var handleIsWritable = false
		var remainingData = Data()
		
		let terminationHandler:DataChannelMonitor.DataChannelTerminationHander
		
		let epollStructure:epoll_event
		weak var manager:DataChannelMonitor?
		
		init(fh:Int32, terminationHandler:@escaping(DataChannelMonitor.DataChannelTerminationHander), manager:DataChannelMonitor) {
			self.fh = fh
			self.terminationHandler = terminationHandler
			
			var buildEpoll = epoll_event()
			buildEpoll.data.fd = fh
			buildEpoll.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
			self.epollStructure = buildEpoll

			self.manager = manager
		}
		
		func hash(into hasher:inout Hasher) {
			hasher.combine(self.fh)
		}
		
		static func == (lhs:OutgoingDataChannel, rhs:OutgoingDataChannel) -> Bool {
			return lhs.fh == rhs.fh
		}
		
		func prepareForTermination() {
			flightGroup.enter()
			writingQueue.async { [weak self] in
				guard let self = self else {
					return
				}
				defer {
					self.flightGroup.leave()
				}
				self.terminationHandler()
				self.manager?.handleEndedLifecycle(writer:self.fh)
			}
		}

		func scheduleDataForWriting(_ inputData:Data) {
			let shouldSchedule:Bool = self.internalSync.sync { () -> Bool in
				self.remainingData.append(inputData)
				if handleIsWritable == true && self.dataWriteScheduled == false {
					self.dataWriteScheduled = true
					return true
				} else {
					return false
				}
			}
			switch shouldSchedule {
				case true:
					self.asyncWriteFunction()
				case false:
					break;
			}
		}
				
		func handleIsAvailableForWriting() {
			let shouldSchedule:Bool = internalSync.sync { () -> Bool in
				if (handleIsWritable == false) {
					handleIsWritable = true
				}
				
				if self.remainingData.count == 0 {
					return false
				}
				
				if dataWriteScheduled == false {
					dataWriteScheduled = true
					return true
				} else {
					return false
				}
			}
			
			switch shouldSchedule {
				case true:
					self.asyncWriteFunction()
				case false:
					break;
			}
		}
		
		func asyncWriteFunction() {
			flightGroup.enter()
			writingQueue.async { [weak self] in
				//setup the async function
				guard let self = self else {
					return
				}
				defer {
					self.flightGroup.leave()
				}
				
				var shouldLoop = false
				//capture the data buffer within `internalSync`
				var remainingData:Data = self.internalSync.sync { () -> Data in
					defer {
						self.remainingData.removeAll(keepingCapacity:true)
					}
					return self.remainingData
				}
				
				repeat {
					var wouldBlock = false
					//try to write the data until we get an error or until 
					do {
						while remainingData.count > 0 {
							remainingData = try self.fh.writeFileHandle(remainingData)
						}
					} catch FileHandleError.error_wouldblock {
						wouldBlock = true
					} catch FileHandleError.error_again {
						wouldBlock = true
					} catch _ {
					}
					
					shouldLoop = self.internalSync.sync {
						//insert the data back into the main buffer
						if (remainingData.count > 0) {
							if (self.remainingData.count > 0) {
								let currentData = self.remainingData
								self.remainingData.removeAll(keepingCapacity:true)
								self.remainingData.append(remainingData)
								self.remainingData.append(currentData)
							} else {
								self.remainingData.append(remainingData)
							}
						}
						
						//refresh the state of the handle's writability
						if wouldBlock {
							self.handleIsWritable = false
						}
						
						//refresh the local data buffer and loop again if there is more data to write and the file handle has not been flagged as unwritable
						if self.handleIsWritable == true && self.remainingData.count > 0 {
							remainingData = self.remainingData
							self.remainingData.removeAll(keepingCapacity:true)
							return true
						} else {
							self.dataWriteScheduled = false
							return false
						}
					}
				} while shouldLoop == true
			}
		}
		
		deinit {
			self.flightGroup.wait()
		}
	}
	
	class TerminationGroup {
		let internalSync = DispatchQueue(label:"com.swiftslash.termination-group.sync", target:process_master_queue)
		var fileHandles:Set<Int32>
		
		let terminationHandler:(pid_t) -> Void
	
		private var associatedPid:pid_t? = nil
	
		init(fhs:Set<Int32>, terminationHandler:@escaping((pid_t) -> Void)) {
			self.fileHandles = fhs
			self.terminationHandler = terminationHandler
		}
	
		func removeHandle(fh:Int32) {
			internalSync.sync {
				fileHandles.remove(fh)
				if (self.fileHandles.count == 0 && associatedPid != nil) {
					self.terminationHandler(associatedPid!)
				}
			}
		}
	
		func setAssociatedPid(_ inputPid:pid_t) {
			internalSync.async { [weak self] in
				guard let self = self else {
					return
				}
				if (self.fileHandles.count == 0) {
					self.terminationHandler(inputPid)
				} else {
					self.associatedPid = inputPid
				}
			}
		}
	}

	let epoll = epoll_create1(0);
	
	let mainQueue = DispatchQueue(label:"com.swiftslash.data-channel-monitor.instance.main", target:process_master_queue)
	var mainLoopLaunched = false
	
	let internalSync = DispatchQueue(label:"com.swiftslash.data-channel-monitor.instance.sync", attributes:[.concurrent], target:process_master_queue)
	var currentAllocationSize:Int32 = 32
	var targetAllocationSize:Int32 = 32
	var currentAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:32)
	var readers = [Int32:IncomingDataChannel]()
	var writers = [Int32:OutgoingDataChannel]()
	
	/*
	TERMINATION GROUPS
	*/
	var exitSync = DispatchQueue(label:"com.swiftslash.data-channel-monitor.instance.termination-group", target:process_master_queue)
	var terminationGroups = [Int32:TerminationGroup]()
	func registerTerminationGroup(fhs:Set<Int32>, handler:@escaping((pid_t) -> Void)) throws -> TerminationGroup {
		let newTerminationGroup = TerminationGroup(fhs:fhs, terminationHandler:handler)
		self.exitSync.async { [weak self, newTerminationGroup, fhs] in
			guard let self = self else {
				return
			}
			for(_, curFH) in fhs.enumerated() {
				self.terminationGroups[curFH] = newTerminationGroup
			}
		}
		return newTerminationGroup
	}
	
	fileprivate func removeFromTerminationGroups(fh:Int32) { 
		self.exitSync.async { [weak self, fh] in
			guard let self = self else {
				return
			}
			let removeCapture = self.terminationGroups.removeValue(forKey:fh)
			if (removeCapture != nil) {
				removeCapture!.removeHandle(fh:fh)
			}
		}
	}
	
	/*
	creating an inbound data channel that is to have its data captured
	*/
	func registerInboundDataChannel(fh:Int32, mode:DataParseMode, dataHandler:@escaping(InboundDataHandler), terminationHandler:@escaping(DataChannelTerminationHander)) -> IncomingDataChannel {
		let newChannel = IncomingDataChannel(fh:fh, triggerMode:mode, dataHandler:dataHandler, terminationHandler:terminationHandler, manager:self)
		self.internalSync.async(flags:[.barrier]) { [weak self, fh, newChannel] in
			guard let self = self else {
				return
			}
			var epollStructure = newChannel.epollStructure
			guard epoll_ctl(self.epoll, EPOLL_CTL_ADD, fh, &epollStructure) == 0 else {
				print("EPOLL ERROR")
				return
			}
			self.readers[fh] = newChannel
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
		return newChannel
	}
	
	/*
	creating a outbound data channel to help facilitate data capture
	*/
	func registerOutboundDataChannel(fh:Int32, initialData:Data? = nil, terminationHandler:@escaping(DataChannelTerminationHander)) -> OutgoingDataChannel {
		let newChannel = OutgoingDataChannel(fh:fh, terminationHandler:terminationHandler, manager:self)		
		internalSync.async(flags:[.barrier]) { [weak self, fh, newChannel] in
			guard let self = self else {
				return
			}
			var epollStructure = newChannel.epollStructure
			guard epoll_ctl(self.epoll, EPOLL_CTL_ADD, fh, &epollStructure) == 0 else {
				print("EPOLL ERROR")
				return
			}
			if initialData != nil && initialData!.count > 0 {
				newChannel.scheduleDataForWriting(initialData!)
			}
			self.writers[fh] = newChannel
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
		return newChannel		
	}
	
	/*
	adds data to the outbound buffer of a file handle that has already been created for writing
	*/
	func broadcastData(fh:Int32, data:Data) throws {
		try internalSync.sync {
			let itemCapture = self.writers[fh]
			if (itemCapture != nil) {
				itemCapture!.scheduleDataForWriting(data)
			} else {
				throw DataChannelMonitorError.invalidFileHandle
			}
		}
	}
	
	/*
	queues a reading file handle to be removed from the channel monitor
	*/
	func handleEndedLifecycle(reader:Int32) {
		internalSync.async(flags:[.barrier]) { [weak self, reader] in
			guard let self = self else {
				return
			}
			let itemCapture = self.readers.removeValue(forKey:reader)
			guard itemCapture != nil else {
				print("ERROR: UNABLE TO REMOVE THE READER FROM THE DATA CHANNEL MONITOR: \(reader)")
				return
			}
			var epollCapture = itemCapture!.epollStructure
			guard epoll_ctl(self.epoll, EPOLL_CTL_DEL, reader, &epollCapture) == 0 else {
				print("ERROR: UNABLE TO CALL EPOLL_CTL_DEL ON FILE HANDLE \(reader)")
				return
			}
			self.removeFromTerminationGroups(fh:reader)
			file_handle_guard.async { [reader] in
				_close(reader)
			}
		}
	}
	
	/*
	queues a writing file handle to be removed from the channel monitor
	*/
	func handleEndedLifecycle(writer:Int32) {
		internalSync.async(flags:[.barrier]) { [weak self, writer] in
			guard let self = self else {
				return
			}
			let itemCapture = self.writers.removeValue(forKey:writer)
			guard itemCapture != nil else {
				print("ERROR: UNABLE TO REMOVE THE WRITER FROM THE DATA CHANNEL MONITOR: \(writer)")
				return
			}
			var epollCapture = itemCapture!.epollStructure
			guard epoll_ctl(self.epoll, EPOLL_CTL_DEL, writer, &epollCapture) == 0 else {
				print("ERROR: UNABLE TO CALL EPOLL-CTL-DEL ON FILE HANDLE \(writer)")
				return
			}
			self.removeFromTerminationGroups(fh:writer)
			file_handle_guard.async { [writer] in
				_close(writer)
			}
		}
	}

	/*
	main loop function.
	*/
	fileprivate func mainLoop() {
		enum EventMode {
			case readableEvent
			case writableEvent
			case readingClosed
			case writingClosed
		}
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
			let (readAllocation, allocationSize, shouldClear) = internalSync.sync { () -> (UnsafeMutablePointer<epoll_event>, Int32, Bool) in
				var returnClear = false
				for (_, curEvent) in handleEvents.enumerated() {
					switch curEvent.value {
						case .readableEvent:
							if readers[curEvent.key] != nil {
								readers[curEvent.key]!.initiateDataCaptureIteration(terminate:false) 
							} else {
								print("`epoll_wait()` received an event for a file handle not stored in this instance. {readable event}")
							}
							break;
						case .writableEvent:
							if writers[curEvent.key] != nil {
								writers[curEvent.key]!.handleIsAvailableForWriting()
							} else {
								print("`epoll_wait()` received an event for a file handle not stored in this instance. {writable event}")
							}
							break;
						case .readingClosed:
							if readers[curEvent.key] != nil {
								readers[curEvent.key]!.initiateDataCaptureIteration(terminate:true)
							} else {
								print("`epoll_wait()` received an event for a file handle not stored in this instance. {reading closed}")
							}
							break;
						case .writingClosed:
							if writers[curEvent.key] != nil {
								writers[curEvent.key]!.prepareForTermination()
							} else {
								print("`epoll_wait()` received an event for a file handle not stored in this instance. {writing closed}")
							}
							break;
							
					}
					if (returnClear == false) {
						returnClear = true
					}
				}
				if (targetAllocationSize != currentAllocationSize) {
					currentAllocation.deallocate()
					currentAllocation = UnsafeMutablePointer<epoll_event>.allocate(capacity:Int(targetAllocationSize))
					currentAllocationSize = targetAllocationSize
					return (currentAllocation, currentAllocationSize, returnClear)
				} else {
					return (currentAllocation, currentAllocationSize, returnClear)
				}
			}
			
			if (shouldClear) {
				handleEvents.removeAll()			
			}

			let pollResult = epoll_wait(epoll, readAllocation, allocationSize, -1)
			if pollResult == -1 && errno == EINTR {
				//there was an error...sleep and try again
				print("EPOLL ERROR")
				usleep(50000) //0.05 seconds
			} else {
				//there was no error...run it
				var i:Int = 0
				while (i < pollResult) {
					let currentEvent = readAllocation[i]
					let pollin = currentEvent.events & UInt32(EPOLLIN.rawValue)
					let pollhup = currentEvent.events & UInt32(EPOLLHUP.rawValue)
					let pollout = currentEvent.events & UInt32(EPOLLOUT.rawValue)
					let pollerr = currentEvent.events & UInt32(EPOLLERR.rawValue)
					
					if (pollhup != 0) {
						//reading handle closed
						handleEvents[currentEvent.data.fd] = .readingClosed
					} else if (pollerr != 0) {
						//writing handle closed
						handleEvents[currentEvent.data.fd] = .writingClosed
					} else if (pollin != 0) {
						//read data available
						handleEvents[currentEvent.data.fd] = .readableEvent
					} else if (pollout != 0) {
						//writing available
						handleEvents[currentEvent.data.fd] = .writableEvent
					}
					i = i + 1;
				}
			}
		}
	}
	
	/*
	PRIVATE
	a convenience function that is called when the number of actively polled handles has changed.
	This function is responsible for ensuring that the main loops epoll_event allocation is always at an appropriate size
	*/
	fileprivate func adjustTargetAllocations() {
		if (((self.readers.count + self.writers.count) * 2) > targetAllocationSize) {
			targetAllocationSize = currentAllocationSize * 2
		} else if (Int(ceil(Double(targetAllocationSize)*0.20)) > (self.readers.count + self.writers.count)) {
			targetAllocationSize = Int32(ceil(Double(currentAllocationSize)*0.5))
		}
		
		if targetAllocationSize < 32 {
			targetAllocationSize = 32
		}
	}
	
	deinit {
		close(epoll)
	}
}