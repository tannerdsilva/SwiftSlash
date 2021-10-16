import Foundation

internal actor TerminationGroup {
	typealias ExitHandler = (Int32?) -> Void
	struct TerminationInfo {
		let didExit:Bool
		let exitCode:Int32?
	}
	fileprivate var fileHandles:Set<Int32>
	fileprivate var associatedPid:pid_t? = nil
	var exitCode:Int32? = nil
	var didExit:Bool = false
	
	fileprivate weak var owningProcess:ProcessInterface? = nil
	
	fileprivate var whenExited:ExitHandler?
	
	init(fhs:Set<Int32>) {
		self.fileHandles = fhs
	}
	
	func includeHandle(fh:Int32) {
		fileHandles.update(with:fh)
	}
	
	func removeHandle(fh:Int32) {
		fileHandles.remove(fh)
		fh.closeFileHandle()
		if (self.fileHandles.count == 0 && associatedPid != nil) {
			self.groupClosed()
		}
		try fh.closeFileHandle()
	}
	
	func setAssociatedPid(_ inputPid:pid_t) {
		self.associatedPid = inputPid
		if (self.fileHandles.count == 0) {
			self.groupClosed()
		}
	}
		
	fileprivate func groupClosed() {
		self.exitCode = self.associatedPid!.getExitCode()
		self.didExit = true
		if (self.whenExited != nil) {
			whenExited!(self.exitCode)
		}
		if (owningProcess != nil) {
			Task.detached { [owningProcess, exitCode] in
				if (exitCode == nil) {
					await owningProcess?.setStatus(.signaled)
				} else {
					await owningProcess?.setStatus(.exited)
				}
			}
		}
	}

	func getExitStatus() -> TerminationInfo {
		return TerminationInfo(didExit:self.didExit, exitCode:self.exitCode)
	}
	
	func setOwningProcess(_ pi:ProcessInterface) async {
		self.owningProcess = pi
		if didExit == true {
			if (exitCode == nil) {
				await pi.setStatus(.signaled)
			} else {
				await pi.setStatus(.exited)
			}
		}
	}
	
	func whenExited(_ handler:@escaping((Int32?) -> Void)) {
		if didExit == true {
			handler(exitCode)
		} else {
			self.whenExited = handler
		}
	}
}

extension ProcessInterface {
	fileprivate func setStatus(_ status:ProcessInterface.Status) async {
		self.status = status
	}
}