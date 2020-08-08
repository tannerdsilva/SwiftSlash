import Foundation
internal class SpawnedProcessMonitor {
	enum SpawnedProcessMonitorError:Error {
		case failedToInitializeBasePipe
	}
	private var basePipe:PosixPipe = PosixPipe()
	private let internalSync = DispatchQueue(label:"com.swiftslash.process-monitor.sync", attributes:[.concurrent], target:swiftslashCaptainQueue)
	
	private let runLoop:DispatchQueue = DispatchQueue(label:"com.swiftslash.process-monitor.run-loop", target:swiftslashCaptainQueue)
	
	private let runLoopAccess = DispatchQueue(label:"com.swiftslash.process-monitor.run-loop.sync"
	private var isLooping:Bool = false
	
	
	init() {
		print("Spawned process monitor has been initialized")
	
	}
	
	func getNotificationPipe() throws -> PosixPipe {
		return try internalSync.sync { () throws -> PosixPipe
			if basePipe.isNullValued == false {
				return basePipe
			} else {
				throw SpawnedProcessMonitorError.failedToInitializeBasePipe
			}
		}
	}
	
	func launchedProcess(_ lpid:pid_t, allocation stackAllocation:UnsafeRawPointer) {
		
	}
	
	func initiateRunloop {
		guard runLoopAccess.sync({ isLooping }) == false else {
			return
		}
		
		runLoop.async { [weak self] in
			while (true) {
			
			}
		}
	}
}

