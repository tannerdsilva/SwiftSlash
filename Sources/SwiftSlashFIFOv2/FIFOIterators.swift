extension FIFO {
	public borrowing func makeSyncConsumer() -> SyncConsumer {
		return SyncConsumer(fifo:copy self)
	}
	public struct SyncConsumer {
		private let fifo:FIFO
		internal init(fifo fifoIn:consuming FIFO) {
			fifo = fifoIn
		}
		public borrowing func next() throws(AlreadyWaiting) -> ConsumeResult {
			return try fifo.nextSynchronous()
		}
	}
}

extension FIFO {
	public borrowing func makeAsyncConsumer() -> AsyncConsumer {
		return AsyncConsumer(fifo:copy self)
	}
	public struct AsyncConsumer {
		private let fifo:FIFO
		internal init(fifo fifoIn:consuming FIFO) {
			fifo = fifoIn
		}
		public borrowing func next(whenTaskCancelled whenConsumingTaskCancelled:FIFO.WhenConsumingTaskCancelled) async throws(AlreadyWaiting) -> FIFO.NextElement {
			return try await fifo.next(whenTaskCancelled: whenConsumingTaskCancelled)
		}
	}
}