/*
LICENSE MIT
copyright (c) tanner silva 2026. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import _Concurrency
import __cswiftslash_threads
import SwiftSlashFIFO
import SwiftSlashPThread

public struct PThreadWorkerEventLoop:PThreadWork {
	public typealias ArgumentType = FIFO<(UnownedJob, UnownedSerialExecutor), Swift.Error>
	public typealias ReturnType = Void
	public typealias ThrowType = Swift.Error
	private let queue:FIFO<(UnownedJob, UnownedSerialExecutor), Swift.Error>
	public init(_ argument:sending ArgumentType) {
		self.queue = argument
	}
	
	public mutating func pthreadWork() throws(Swift.Error) -> sending Void {
		let consumer = queue.makeSyncConsumerBlocking()
		while let (job, executor) = try consumer.next() {
			job.runSynchronously(on:executor)
		}
	}
}

public final class PThreadSerialExecutor:SerialExecutor {
    private let queue:FIFO<(UnownedJob, UnownedSerialExecutor), Swift.Error>
	private let running:Running<PThreadWorkerEventLoop>
	public init(thread:consuming Running<PThreadWorkerEventLoop>, fifo:FIFO<(UnownedJob, UnownedSerialExecutor), Swift.Error>) {
		self.running = thread
		self.queue = fifo
	}
    deinit {
		// try? is acceptable here because we do not care if the queue is already finished.
		try? queue.finish()
    }
    public func enqueue(_ job:consuming ExecutorJob) {
        // FIFO is thread-safe and handles yielding the job across threads.
        _ = queue.yield((UnownedJob(job), asUnownedSerialExecutor()))
    }
}
