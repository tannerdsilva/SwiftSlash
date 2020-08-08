import Foundation
import Cepoll

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
		
		var epollStructure = epoll_event()
		let mainQueue = DispatchQueue(label:"com.swiftslash.instance.data-channel-monitor.reading", target:dataCaptureQueue)
		
		var dataBuffer = Data()
	
		let triggerMode:TriggerMode
		let dataHandler:DataIntakeHandler
		let terminationHandler:GenericHandler
	
		init(fh:Int32, triggerMode:TriggerMode, dataHandler:@escaping(DataIntakeHandler), terminationHandler:@escaping(GenericHandler)) {
			self.fh = fh
			
			self.epollStructure.data.fd = fh
			self.epollStructure.events = UInt32(EPOLLIN.rawValue) | UInt32(POLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
			
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
			do {
				while try fh.pollReading(timeoutMilliseconds:-1) != .pipeTerm {
					do {
						let capturedData = try self.fh.readFileHandle()
					} catch let error {
						switch error {
							case FileHandleError.error_pipe:
								break;
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
	//	let fh:Int32
	//
	//	let main:DispatchQueue = DispatchQueue(label:".com.swiftslash.data-channel-monitor.")
	}
//

	let epoll = epoll_create1(0);
	
	let internalSync = DispatchQueue(label:"com.swiftslash.data-channel-monitor.global-instance.sync", target:swiftslashCaptainQueue)
	let mainQueue = DispatchQueue(label:"com.swiftslash.data-channel-monitor.main.sync", target:swiftslashCaptainQueue)
	var mainLoopLaunched = false

	var readers = [Int32:IncomingChannel]()
	var writers = [Int32:OutgoingHandler]()

	func registerInboundDataChannel(fh:Int32, mode:IncomingChannel.TriggerMode, dataHandler:@escaping(DataIntakeHandler), terminationHandler:@escaping(GenericHandler)) {
		internalSync.sync(flags:[.barrier]) {
			self.readers[fh] = IncomingChannel(fh:fh, triggerMode:mode, dataHandler:dataHandler, terminationHandler:terminationHandler)
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
	
	}
}