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
	}
	
	func setAssociatedPid(_ inputPid:pid_t) {
		self.associatedPid = inputPid
		if (self.fileHandles.count == 0) {
			self.groupClosed()
		}
	}
	
	func getExitStatus() -> TerminationInfo {
		return TerminationInfo(didExit:self.didExit, exitCode:self.exitCode)
	}
	
	func whenExited(_ handler:@escaping((Int32?) -> Void)) {
		if didExit == true {
			handler(exitCode)
		} else {
			self.whenExited = handler
		}
	}
	
	fileprivate func groupClosed() {
		self.exitCode = self.associatedPid!.getExitCode()
		self.didExit = true
		if (self.whenExited != nil) {
			whenExited!(self.exitCode)
		}
	}
}