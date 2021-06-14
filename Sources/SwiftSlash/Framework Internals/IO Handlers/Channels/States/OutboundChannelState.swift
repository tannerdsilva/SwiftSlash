import Foundation

class OutboundChannelState:Hashable {
	let fh:Int32
	let internalSync = DispatchQueue(label:"com.swiftslash.file-handle-broadcast.instance.sync", target:process_master_queue)
	
	var outboundBuffer = Data()
	
	init(fh:Int32) {
		self.fh = fh
	}
	
	func broadcast(_ dataToWrite:Data) {
		self.internalSync.sync {
			outboundBuffer.append(contentsOf:dataToWrite)
			self._flushDataToHandle()
		}
	}
	
	func channelWriteableEvent() {
		return self.internalSync.sync {
			self._flushDataToHandle()
		}
	}
	
	fileprivate func _flushDataToHandle() {
		do {
			while outboundBuffer.count > 0 {
				let remainingData = try self.fh.writeFileHandle(self.outboundBuffer)
				outboundBuffer.removeAll(keepingCapacity:true)
				if (remainingData.count > 0) {
					outboundBuffer.append(remainingData)
				}
			}
		} catch FileHandleError.error_again {
		} catch FileHandleError.error_wouldblock {
		} catch FileHandleError.error_pipe {
		} catch _ {}
	}
	
	func hash(into hasher:inout Hasher) {
		hasher.combine(fh)
	}
	
	static func == (lhs:OutboundChannelState, rhs:OutboundChannelState) -> Bool {
		return (lhs.fh == rhs.fh)
	}
}
