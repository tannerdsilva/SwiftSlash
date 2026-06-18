/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

bedrock

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
    public init(_ argument: consuming ArgumentType) {
    	self.queue = argument
    }
    
    public mutating func pthreadWork() throws(Swift.Error) -> Void {
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
        queue.finish()
    }
    public func enqueue(_ job:consuming ExecutorJob) {
        // FIFO is thread-safe and handles yielding the job across threads.
        _ = queue.yield((UnownedJob(job), asUnownedSerialExecutor()))
    }
    public borrowing func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        return UnownedSerialExecutor(ordinary:self)
    }
}
