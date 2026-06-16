/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

bedrock

*/

import _Concurrency
import __cswiftslash_threads
import SwiftSlashFIFO
import SwiftSlashPThread

/// A discrete worker struct designed to run an event loop on a pthread.
/// This struct conforms to PThreadWork and encapsulates the logic for 
/// pulling jobs from the FIFO queue and executing them.
public struct PThreadWorkerEventLoop:PThreadWork {
    /// The argument type passed to the worker (our FIFO queue).
    public typealias ArgumentType = FIFO<(UnownedJob, UnownedSerialExecutor), Swift.Error>
    
    /// The return type of the work function (Void).
    public typealias ReturnType = Void
    
    /// The error type allowed by the work function.
    public typealias ThrowType = Swift.Error
    
    /// The FIFO queue instance containing the jobs to process.
    private let queue:FIFO<(UnownedJob, UnownedSerialExecutor), Swift.Error>

    /// Initializer required by the PThreadWork protocol.
    /// This consumes the queue argument to transfer ownership to the worker instance.
    public init(_ argument: consuming ArgumentType) {
    	self.queue = argument
    }
    
    /// The main entry point for the pthread work loop.
    /// It blockingly consumes jobs from the queue and executes them one by one.
    public mutating func pthreadWork() throws(Swift.Error) -> Void {
		let consumer = queue.makeSyncConsumerBlocking()
        // Continuously consume elements. 'next()' returns nil when the FIFO is finished.
        while let (job, executor) = try consumer.next() {
            job.runSynchronously(on: executor)
        }
    }
}

public final class PThreadSerialExecutor:SerialExecutor {
	fileprivate enum State {
		case initializing
		case running(Running<PThreadWorkerEventLoop>)
	}
    private let queue:FIFO<UnownedJob, Swift.Error> = FIFO()
	private let running:Running<PThreadWorkerEventLoop>
	init(thread:consuming Running<PThreadWorkerEventLoop>) {
		self.running = thread
	}
    deinit {
        queue.finish()
    }
    public func enqueue(_ job:consuming ExecutorJob) {
        // FIFO is thread-safe and handles yielding the job across threads.
        _ = queue.yield(UnownedJob(job))
    }
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        return UnownedSerialExecutor(ordinary:self)
    }
}
