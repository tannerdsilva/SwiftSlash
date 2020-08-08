import Foundation

internal class StdDataChannelMonitor {
	typealias DataIntakeHandler = (Data) -> Void
	typealias GenericHandler = () -> Void
	
	static let dataCaptureQueue = DispatchQueue(label:"com.swiftslash.global.data-channel-monitor.reading", attributes:[.concurrent], target:swiftslashCaptainQueue)
	static let dataBroadcastQueue = DispatchQueue(label:"com.swiftslash.global.data-channel-monitor.writing", attributes:[.concurrent], target:swiftslashCaptainQueue)
	
	class IncomingChannel:Equatable {
		enum TriggerMode {
			case lineBreakParsed;
			case lineBreakUnparsed;
			case immediate;
		}
		let fh:Int32
		
		let mainGroup = DispatchGroup()
		let mainQueue = DispatchQueue(label:"com.swiftslash.instance.data-channel-monitor.reading", target:dataCaptureQueue)
		
		var dataBuffer = Data()
	
		let triggerMode:TriggerMode
		let dataHandler:DataIntakeHandler
		let terminationHandler:GenericHandler
	
		init(fh:Int32, triggerMode:TriggerMode, dataHandler:@escaping(DataIntakeHandler), terminationHandler:@escaping(GenericHandler)) {
			self.fh = fh

			self.triggerMode = triggerMode
		
			self.dataHandler = dataHandler
			self.terminationHandler = terminationHandler
			
			self.mainQueue.async { [weak self] in
				guard let self = self else {
					return
				}
				self.mainLoop()
			}
		}
	
		//this main loop is called as soon as 
		private func mainLoop() {
			mainGroup.enter()
			defer {
				mainGroup.leave()
			}
			do {
				while try fh.pollReading(timeoutMilliseconds:-1) != .pipeTerm {
					do {
						let capturedData = try self.fh.readFileHandle()
					} catch let error {
						switch error {
							case FileHandleError.error_pipe:
								loopRun = false;
							default:
								break;
						}
					}
				}
			} catch _ { }
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
		let fh:Int32
	
		let main:DispatchQueue = DispatchQueue(label:".com.swiftslash.data-channel-monitor.")
	}

	let internalSync = DispatchQueue(label:"com.swiftslash.data-channel-monitor.global-instance.sync", target:swiftslashCaptainQueue)
	let mainQueue = DispatchQueue(label:"com.swiftslash.data-channel-monitor.main.sync", target:swiftslashCaptainQueue)
	var mainLoopRunning = false

	var readers = [Int32:IncomingChannel]()
	var writers = [Int32:DataHandler]()

	func registerInboundDataChannel(fh:Int32, dataHandler:@escaping(DataIntakeHandler), terminationHandler:@escaping(GenericHandler)) {
		internalSync.async(flags:[.barrier]) { [weak self, fd, handler] in
			guard let self = self else {
				return
			}
			self.readers[fd] = IncomingChannel(fh:fh, dataHandler:dataHandler, terminationHandler:terminationHandler)
			if (self.mainLoopRunning == false) {
				//launch the main loop if it is not already running
				self.mainLoopRunning = true
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
	
	}
}