/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Testing
import SwiftSlashPThreadSerialExecutor
import SwiftSlashFIFO
import SwiftSlashPThread
@Suite("SwiftSlashTests",
	.serialized
)
internal struct SwiftSlashTests {}

/// a process may only launch one child process at a time. no step in regards to producing a child process is reentrant safe. this actor enforces this strictly.
@globalActor internal actor SwiftSlashPThreadBackedExecutor:GlobalActor {
	private let serialExecutor:PThreadSerialExecutor

	internal init() {
		let lt:Running<PThreadWorkerEventLoop>
		let fifo = try! FIFO<(UnownedJob, UnownedSerialExecutor), Swift.Error>()
		do {
			lt = try PThreadWorkerEventLoop.launch(fifo)
		} catch let error {
			fatalError("failed to launch pthread for global serialization actor: \(error)")
		}
		self.serialExecutor = PThreadSerialExecutor(thread:lt, fifo:fifo)
	}

	internal nonisolated var unownedExecutor:UnownedSerialExecutor {
		serialExecutor.asUnownedSerialExecutor()
	}

	/// the global actor that is used to serialize the launch of child processes.
	internal static let shared = SwiftSlashPThreadBackedExecutor()
}
