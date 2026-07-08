extension FIFO {
	public borrowing func makeSyncConsumerNonBlocking() -> SyncConsumerNonBlocking {
		return SyncConsumerNonBlocking(fifo:copy self)
	}
	public struct SyncConsumerNonBlocking {
		private let fifo:FIFO
		internal init(fifo fifoIn:consuming FIFO) {
			fifo = fifoIn
		}
		public borrowing func next() throws(Failure) -> Element? {
			switch try! fifo.nextSynchronous() {
				case .wouldBlock:
					return nil
				case .element(let element):
					return element
				case .capped(let result):
					switch result {
						case .success:
							return nil
						case .failure(let err):
							throw err
					}
			}
		}
	}
}

extension FIFO {
	public borrowing func makeSyncConsumerBlocking() -> SyncConsumerBlocking {
		return SyncConsumerBlocking(fifo:copy self)
	}
	public struct SyncConsumerBlocking {
		private let fifo:FIFO
		internal init(fifo fifoIn:consuming FIFO) {
			fifo = fifoIn
		}
		public borrowing func next() throws(Failure) -> Element? {
			let syncWaiter = FIFO.SyncWaiter()
			switch try! fifo.nextSynchronous(waiter:syncWaiter) {
				case .wouldBlock:
					switch syncWaiter.wait() {
						case .success(let element):
							return element
						case .failure(let err):
							throw err
						case .none:
							return nil
					}
				case .element(let element):
					return element
				case .capped(let result):
					switch result {
						case .success:
							return nil
						case .failure(let err):
							throw err
					}
			}
		}
	}
}

extension FIFO {
	public borrowing func makeAsyncConsumerExplicit() -> AsyncConsumerExplicit {
		return AsyncConsumerExplicit(fifo:copy self)
	}
	public struct AsyncConsumerExplicit {
		private let fifo:FIFO
		internal init(fifo fifoIn:consuming FIFO) {
			self.fifo = fifoIn
		}
		public borrowing func next(whenTaskCancelled whenConsumingTaskCancelled:FIFO.WhenConsumingTaskCancelled = .noAction) async throws(Failure) -> ConsumeResult {
			switch try! await fifo.next(whenTaskCancelled: whenConsumingTaskCancelled) {
				case .success(let element):
					return .element(element)
				case .failure(let error):
					return .capped(.failure(error))
				case .none:
					return .capped(.success(()))
			}
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
		public borrowing func next(whenTaskCancelled whenConsumingTaskCancelled:FIFO.WhenConsumingTaskCancelled = .noAction) async throws(Failure) -> Element? {
			switch try! await fifo.next(whenTaskCancelled: whenConsumingTaskCancelled) {
				case .some(let elementResult):
					switch elementResult {
						case .success(let element):
							return element
						case .failure(let error):
							throw error
					}
				case .none:
					return nil
			}
		}
	}
}