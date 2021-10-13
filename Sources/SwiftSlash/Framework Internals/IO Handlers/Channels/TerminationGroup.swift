import Foundation

actor TerminationGroup {
	var fileHandles:Set<Int32>
	let terminationHandler:(pid_t) -> Void
	private var associatedPid:pid_t? = nil
	
	init(fhs:Set<Int32>, terminationHandler:@escaping((pid_t) -> Void)) {
		self.fileHandles = fhs
		self.terminationHandler = terminationHandler
	}
	
	func include(fh:Int32) {
		fileHandles.update(with:fh)
	}
	
	func removeHandle(fh:Int32) {
		fileHandles.remove(fh)
		if (self.fileHandles.count == 0 && associatedPid != nil) {
			self.terminationHandler(associatedPid!)
		}
	}
	
	func setAssociatedPid(_ inputPid:pid_t) {
		if (self.fileHandles.count == 0) {
			self.terminationHandler(inputPid)
		} else {
			self.associatedPid = inputPid
		}
	}
}