/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Synchronization
import SwiftSlashOneShotLatch

public final class Future<Produced:Sendable, Failure:Swift.Error & Swift.Sendable>:Sendable {
	/// thrown when a result is attempted to be assigned to a future but the future is already in a finished state (either with a result, an error, or a cancellation).
	public struct InvalidStateError:Swift.Error {}

	/// a tool used by a user waiting for a result of a future instance. this tool, specifically, is used to block the waiting thread until the future produces a result, allowing the user to synchronously wait for a result from the future.
	public final class SyncWaiter:Sendable {
		internal let uid:UInt64 = UInt64.random(in:1...UInt64.max)
		private let latch:OneShotLatch<Result<Produced, Failure>?>
		internal init() {
			latch = OneShotLatch()
		}
		public func wait() -> Result<Produced, Failure>? {
			return try! latch.wait()
		}
		internal borrowing func notify(with resultToAssign:sending Result<Produced, Failure>?) {
			try! latch.fire(resultToAssign)
		}
	}
	public typealias CodeBlockWaiter = @Sendable (Result<Produced, Failure>?) -> Void
		
	private let core:Core

	/// create a new future with an optional handler for deallocating successful results on the final dereferencing of this instance.
	public init() {
		core = Core()
	}
}

// MARK: Assignment
extension Future {
	/// sets the result of the future to a successful value. if the future already has a result (either a success, a failure, or a cancellation), this function will throw an error.
	/// - parameters:
	/// 	- result: the successful result to set on the future.
	/// - throws: an error if the future already has a result (either a success, a failure, or a cancellation).
	@discardableResult public func setSuccess(_ result:sending Produced) throws(InvalidStateError) -> Set<UInt64> {
		return try core.assign(.result(result))
	}
	
	/// sets the result of the future to a failure value. if the future already has a result (either a success, a failure, or a cancellation), this function will throw an error.
	/// - parameters:
	/// 	- error: the failure error to set on the future.
	/// - throws: an error if the future already has a result (either a success, a failure, or a cancellation).
	@discardableResult public func setFailure(_ error:sending Failure) throws(InvalidStateError) -> Set<UInt64> {
		return try core.assign(.thrown(error))
	}

	/// cancels the future. if the future already has a result (either a success, a failure, or a cancellation), this function will throw an error.
	/// - throws: an error if the future already has a result (either a success, a failure, or a cancellation).
	@discardableResult public func cancel() throws(InvalidStateError) -> Set<UInt64> {
		return try core.assign(.cancelled)
	}
}

extension Future {
	/// returns the basic state of a future, indicating whether it has a result or not.
	/// - returns: `true` if the future has a result (either a success, a failure, or a cancellation), or `false` if the future is still pending a result.
	public func hasResult() -> Bool {
		return core.hasResult()
	}

	/// cancels an individual waiter of a specified uid without affecting the state of the future. this is primarily useful for task-local cancellations.
	/// - parameters:
	/// 	- waiterID: the uid of the waiter to cancel.
	/// - returns: true if the waiter was found and cancelled, false if the waiter was not found (either because it was already notified or because it never existed).
	@discardableResult public func cancelWaiter(_ waiterID:UInt64) -> Bool {
		do {
			return try core.cancelWaiter(waiterID)
		} catch {
			return false
		}
	}

	/// registers a code block to be executed when the future produces a result. if the future already has a result, the code block will be executed immediately with the result.
	/// - parameters:
	/// 	- codeToRun: the code block to execute when the future produces a result. the code block will be executed with an optional result, which will be nil if the future was cancelled before it could produce a result.
	/// - returns: the uid of the registered code block waiter, or nil if the future already has a result and the code block was executed immediately.
	@discardableResult public func whenResult(_ codeToRun:@escaping CodeBlockWaiter) -> UInt64? {
		return core.registerCodeBlockWaiter(codeToRun)
	}

	/// creates a new synchronous waiter that can be used to block the current thread until the future produces a result. if the future already has a result, the waiter will be notified immediately with the result.
	/// - returns: a new synchronous waiter that can be used to block the current thread until the future produces a result.
	public func waitSynchronously() -> SyncWaiter {
		let waiter = SyncWaiter()
		_ = core.registerResultWaiter(waiter)
		return waiter
	}

	public borrowing func result() async -> Result<Produced, Failure>? {
		return await result(throwing: Never.self, onCurrentTaskCancellation: fatalError("this function cannot throw because the error type is Never"))
	}

	public borrowing func result<E>(throwing _:E.Type, onCurrentTaskCancellation throwOnTaskCancellation:@autoclosure () -> E) async throws(E) -> Result<Produced, Failure>? where E:Swift.Error {
		let cancelID:Atomic<UInt64> = .init(0)
		let didCallCancellationHandler:Atomic<Bool> = .init(false)
		let returnResult = await withTaskCancellationHandler { () async -> Result<Produced, Failure>? in
			guard didCallCancellationHandler.load(ordering:.acquiring) == false else {
				return nil
			}
			return await withUnsafeContinuation({ (cont:UnsafeContinuation<Result<Produced, Failure>?, Never>) in
				if let uid = core.registerAsyncAwaiter(cont) {
					cancelID.store(uid, ordering:.releasing)
					if didCallCancellationHandler.load(ordering:.acquiring) == true {
						_ = try? core.cancelWaiter(uid)
					}
				}
			})
		} onCancel: {
			didCallCancellationHandler.store(true, ordering:.releasing)
			let cancelID = cancelID.load(ordering:.acquiring)
			if cancelID != 0 {
				_ = try? core.cancelWaiter(cancelID)
			}
		}
		if didCallCancellationHandler.load(ordering:.acquiring) && returnResult == nil {
			throw throwOnTaskCancellation()
		} else {
			return returnResult
		}
	}
}

// MARK: Core
extension Future {
	internal struct Core:~Copyable {

		/// conveys one of the three possible "finishing operations" that can occur on a future, allowing it to produce a result for any waiters.
		internal enum ResultErrorCancelled:Sendable {
			/// the future produced a result
			case result(Produced)
			/// the future threw an error
			case thrown(Failure)
			/// the future was cancelled before it could produce a result.
			case cancelled
			/// a tool to convert the ResultErrorCancelled into a more traditional Result type for use in waiters and other places where it is more ergonomic to work with a Result type. this will return nil if the future was cancelled, and will return a Result with either the produced value or the thrown error if the future was not cancelled.
			internal func toResult() -> Result<Produced, Failure>? {
				switch self {
					case .result(let produced):
						return .success(produced)
					case .thrown(let error):
						return .failure(error)
					case .cancelled:
						return nil
				}
			}
		}

		/// conveys one of the two possible types of waiters that can wait on a future.
		private enum WaiterInfo:Sendable {
			/// there is a "synchronous waiter" with a blocked thread that is waiting for the result to be set before it can return.
			case syncBlock(SyncWaiter)
			/// there is a "code block waiter" that is waiting for the result to be set before it can execute a code block with the result.
			case codeNotify(@Sendable (Result<Produced, Failure>?) -> Void)
			/// there is an "async/await waiter" that is waiting for the result to be set before it can resume the async context with the result.
			case asyncAwaiter(UnsafeContinuation<Result<Produced, Failure>?, Never>)
		}
		
		/// the state of the future, which can either be pending (with a list of waiters) or finished (with a result, an error, or a cancellation).
		private enum State:Sendable {
			/// the future is pending and has a list of waiters that are waiting for the result to be notified.
			case pending([(UInt64, WaiterInfo)])
			/// the future is finished and has a result, an error, or a cancellation.
			case finished(ResultErrorCancelled)
		}

		/// an internal tool to convey if a waiter should wait or immediately return when attempting to wait on the future.
		private enum WaitOrImmediatelyReturn {
			/// there is no result so the waiter must wait for the result to be set before it can return.
			case wait(WaiterInfo)
			/// there is already a result, so the waiter can return immediately with the result.
			case immediatelyReturn(ResultErrorCancelled)
		}

		/// an internal mechanism used in the trinity of "registration" functions.
		private enum WaiterOrResult {
			/// pertains to a waiter of the specified uid.
			case waiter(UInt64)
			/// pertains to a result, error, or cancellation that has already been set on the future.
			case result(ResultErrorCancelled)
		}

		/// the instance state of the future core, guarded by the state mutex.
		private let stateMutex:Mutex<State> = .init(State.pending([]))

		/// returns true if the future has a result, error, or cancellation, and false if the future is still pending a result.
		internal func hasResult() -> Bool {
			return stateMutex.withLock({
				switch $0 {
					case .pending(_):
						return false
					case .finished(_):
						return true
				}
			})
		}

		/// cancels an individual waiter of a specified uid without affecting the state of the future. this is primarily useful for task-local cancellations.
		/// - parameters:
		/// 	- uid: the uid of the waiter to cancel.
		/// - returns: true if the waiter was found and cancelled, false if the waiter was not found (either because it was already notified or because it never existed).
		internal borrowing func cancelWaiter(_ uid:UInt64) throws(InvalidStateError) -> Bool {
			switch try stateMutex.withLock({ (state) throws(InvalidStateError) -> WaiterInfo? in
				switch state {
					case .pending(var waiters):
						for (i, (iuid, wi)) in waiters.enumerated() {
							if iuid == uid {
								waiters.remove(at: i)
								state = .pending(waiters)
								return wi
							}
						}
						return nil
					case .finished(_):
						throw InvalidStateError()
				}
			}) {
				case .none:
					return false
				case .some(let foundWaiter):
					switch foundWaiter {
						case .syncBlock(let syncWaiter):
							syncWaiter.notify(with: nil)
						case .codeNotify(let notifyBlock):
							notifyBlock(nil)
						case .asyncAwaiter(let continuation):
							continuation.resume(returning: nil)
					}
					return true
			}

		}

		/// registers a synchronous waiter to wait for the result of the future. if the future is already finished, the waiter will be notified immediately with the result.
		internal borrowing func registerResultWaiter(_ waiter:consuming SyncWaiter) -> UInt64? {
			switch stateMutex.withLock({ (state) -> WaiterOrResult in
				switch state {
					// the future is still pending a result, so we must register the synchronous waiter to be notified when the result is set.
					case .pending(var waiters):
						// store the waiter and its uid in the list of waiters for the future.
						waiters.append((waiter.uid, .syncBlock(waiter)))
						// save the updated state back into the future's state mutex.
						state = .pending(waiters)
						// return the result of this work.
						return .waiter(waiter.uid)
					// the future is already finished, so we can immediately notify the synchronous waiter with the result.
					case .finished(let result):
						return .result(result)
				}
			}) {
				case .waiter(let waiterUID):
					return waiterUID
				case .result(let result):
					waiter.notify(with: result.toResult())
					return nil
			}
		}

		/// registers a code block waiter to wait for the result of the future. if the future is already finished, the code block will be executed immediately with the result.
		/// - parameters:
		/// 	- codeToNotify: the code block to execute when the future produces a result. the code block will be executed with an optional result, which will be nil if the future was cancelled before it could produce a result.
		/// - returns: the uid of the registered code block waiter, or nil if the future already has a result and the code block was executed.
		internal borrowing func registerCodeBlockWaiter(_ codeToNotify:consuming @escaping CodeBlockWaiter) -> UInt64? {
			switch stateMutex.withLock({ (state) -> WaiterOrResult in
				switch state {
					// the future is still pending a result, so we must register the code block waiter to be notified when the result is set.
					case .pending(var waiters):
						// generate a unique id for the waiter and register it with the future's state.
						let uid = UInt64.random(in:1...UInt64.max)
						// store the waiter and its uid in the list of waiters for the future.
						waiters.append((uid, .codeNotify(codeToNotify)))
						// save the updated state back into the future's state mutex.
						state = .pending(waiters)
						// return the result of this work.
						return .waiter(uid)
					// the future is already finished, so we can immediately notify the code block waiter with the result.
					case .finished(let result):
						return .result(result)
				}
			}) {
				/// the waiter was registered and is waiting for the result to be set, so we return the uid of the waiter to the caller.
				case .waiter(let waiterUID):
					return waiterUID
				/// the future is already finished, so we immediately notify the code block waiter with the result and return nil to indicate that the waiter was not registered.
				case .result(let result):
					codeToNotify(result.toResult())
					return nil
			}
		}

		/// registers an async awaiter to wait for the result of the future. if the future is already finished, the continuation will be resumed immediately with the result.
		/// - parameters:
		/// 	- continuation: the continuation to resume when the future produces a result.
		/// - returns: the uid of the registered async awaiter, or nil if the future already has a result and the continuation was resumed immediately.
		internal borrowing func registerAsyncAwaiter(_ continuation:consuming UnsafeContinuation<Result<Produced, Failure>?, Never>) -> UInt64? {
			switch stateMutex.withLock({ (state) -> WaiterOrResult in
				switch state {
					// the future is still pending a result, so we must register the async awaiter to be resumed when the result is set.
					case .pending(var waiters):
						// generate a unique id for the async awaiter and register it with the future's state.
						let uid = UInt64.random(in:1...UInt64.max)
						// store the async awaiter and its uid in the list of waiters for the future.
						waiters.append((uid, .asyncAwaiter(continuation)))
						// save the updated state back into the future's state mutex.
						state = .pending(waiters)
						// return the result of this work.
						return .waiter(uid)
					// the future is already finished, so we can immediately resume the async awaiter with the result.
					case .finished(let result):
						return .result(result)
				}
			}) {
				// the async awaiter was registered and is waiting for the result to be set, so we return the uid of the async awaiter to the caller.
				case .waiter(let waiterUID):
					return waiterUID
				// the future is already finished, so we immediately resume the async awaiter with the result and return nil to indicate that the async awaiter was not registered.
				case .result(let result):
					continuation.resume(returning: result.toResult())
					return nil
			}
		}

		/// assigns a result, error, or cancellation to the future and notifies all waiters. if the future is already finished, this function will throw an error.
		/// - parameters:
		/// 	- result: the result, error, or cancellation to assign to the future.
		/// - throws: an error if the future is already finished.
		/// - returns: a set of the uids of the waiters that were notified of the assignment of the result, error, or cancellation.
		internal borrowing func assign(_ result:ResultErrorCancelled) throws(InvalidStateError) -> Set<UInt64> {
			// retrieve all waiters from the state.
			let waiters:[(UInt64, WaiterInfo)] = try stateMutex.withLock({ (state) throws(InvalidStateError) in
				switch state {
					case .pending(let waiters):
						state = .finished(result)
						return waiters
					case .finished(_):
						throw InvalidStateError()
				}
			})

			var notifiedWaiters:Set<UInt64> = []
			let toResult = result.toResult()
			for (uid, waiter) in waiters {
				defer { notifiedWaiters.insert(uid) }
				switch waiter {
					case .syncBlock(let syncWaiter):
						syncWaiter.notify(with:toResult)
					case .codeNotify(let notifyBlock):
						notifyBlock(toResult)
					case .asyncAwaiter(let continuation):
						continuation.resume(returning:toResult)
				}
			}
			return notifiedWaiters
		}

		deinit {
			// check the future state to determine if there are pending waiters that need to be cancelled.
			switch stateMutex.withLock({ (state) -> [(UInt64, WaiterInfo)]? in
				switch state {
					// there are pending waiters that need to be cancelled, so we return the list of waiters to be cancelled.
					case .pending(let waiters):
						state = .finished(.cancelled) // mark as finished to prevent new waiters
						return waiters
					// the future is already finished, so there are no waiters to cancel.
					case .finished:
						return nil
				}
			}) {
				case .none:
					// there are no waiters to cancel, so we can safely return from the deinit.
					return
				case .some(let waitersToCancel):
					// there are waiters to cancel, so we iterate through the list of waiters and notify them with nil to indicate that the future has been cancelled.
					for (_, waiter) in waitersToCancel {
						switch waiter {
							case .syncBlock(let syncWaiter):
								syncWaiter.notify(with: nil)
							case .codeNotify(let notifyBlock):
								notifyBlock(nil)
							case .asyncAwaiter(let continuation):
								continuation.resume(returning: nil)
						}
					}
			}
		}
	}
}