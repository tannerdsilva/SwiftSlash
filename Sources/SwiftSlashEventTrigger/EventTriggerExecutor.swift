// import SwiftSlashFIFO
// import SwiftSlashPThread

// extension EventTrigger {
	
// 	internal final class EventLoopExecutor:SerialExecutor {
// 		private struct PThread:PThreadWork {
// 			internal typealias ArgumentType = FIFO<(Swift.UnownedJob, Swift.UnownedSerialExecutor), Swift.Error>
// 			internal typealias ReturnType = Void
// 			internal typealias ThrowType = Swift.Error
// 			private let queue:FIFO<(Swift.UnownedJob, Swift.UnownedSerialExecutor), Swift.Error>
// 			internal init(_ argument:sending ArgumentType) {
// 				self.queue = argument
// 			}

// 			internal mutating func pthreadWork() throws(Swift.Error) -> sending Void {
// 				let consumer = queue.makeSyncConsumerBlocking()
// 				while let (job, executor) = try consumer.next() {
// 					job.runSynchronously(on:executor)
// 				}
// 			}
// 		}
// 		private let eventLoopWorker:PThread
// 		private let queue:FIFO<(Swift.UnownedJob, Swift.UnownedSerialExecutor), Swift.Error>
// 		internal init() {
// 			self.queue = try! FIFO()
// 			self.eventLoopWorker = PThread(queue)
// 		}
// 		internal func enqueue(_ job:consuming ExecutorJob) {
// 			_ = queue.yield((Swift.UnownedJob(job), Swift.UnownedSerialExecutor(ordinary:self)))
// 		}
// 	}
// }