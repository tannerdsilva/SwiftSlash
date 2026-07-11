/*
LICENSE MIT
copyright (c) tanner silva 2026. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_threads
import SwiftSlashFuture
import Synchronization

// this file articulates a lot of unsafe and unbalanced memory management. the scope of the unsafety is limited to this single file, therefore, any possible errors or mishandlings of the memory should be visible from this file alone. the file consists of mostly private and fileprivate functions, with only a small handful of public/internal entrypoints being provided.

/// runs any given arbitrary function on a newly created pthread.
public func run<R>(_ work:consuming @escaping @Sendable () throws -> R) async throws(PThreadLaunchFailure) -> Result<R, Swift.Error>? where R:Sendable {
	let launchedThread = try GenericPThread.launch(work)
	return await launchedThread.workResult()
}

/// launch a pthread with a given function and return the running pthread.
public func launch<R>(_ work:consuming @escaping @Sendable () throws -> R) throws(PThreadLaunchFailure) -> Running<GenericPThread<R>> where R:Sendable {
	return try GenericPThread.launch(work)
}

extension PThreadWork {
	public static func launch(_ arg:consuming ArgumentType) throws(PThreadLaunchFailure) -> Running<Self> {
		return try launchPThread(work:Self.self, argument:arg).get()
	}
	public static func run(_ arg:consuming ArgumentType) async throws -> Result<ReturnType, ThrowType>? {
		let launched = try Self.launch(arg)
		return try await launched.workResult(throwingOnCurrentTaskCancellation:CancellationError.self, taskCancellationError:CancellationError())
	}
}

extension PThreadWork {
	// this is a bridge function that allows the c code to call the allocator function for the specific type in question. this is a critical step in the pthread lifecycle because this is where the initial argument is consumed.
	fileprivate init(_ arg:any Sendable) {
		self = Self(arg as! ArgumentType)
	}
	// this is a bridge function that allows the primary work implementation to run and return into the future as it needs to when it is called from the pthread.
	fileprivate mutating func firePThreadWork(into future:consuming Future<Result<any Sendable, any Swift.Error>, Never>) {
		let result:Result<any Sendable, any Swift.Error>
		do {
			result = .success(try pthreadWork())
		} catch let error {
			result = .failure(error)
		}
		try! future.setSuccess(result)		
	}
	// builds the strictly typed future with deallocator function that the pthread worker will use.
	fileprivate static func buildReturnFuture() -> Future<Result<any Sendable, any Swift.Error>, Never> {
		return Future<Result<any Sendable, any Swift.Error>, Never>()
	}
}

/// represents the memory space that is initialized and used within a pthread to accomplish a task.
fileprivate struct Workspace {
	
	/// the instance of the workspace that is being used in the pthread.
	private var workspaceInstance:any PThreadWork
	/// the type of workspace that is being used in the pthread. the type is not known at compile time, so it is stored here for use in the pthread.
	private let workspaceType:any PThreadWork.Type
	/// the future for pthread configuration. this is set to success when the pthread is configured, running its work, and ready to be canceled. after a result is passed into the return future, this future is set to nil.
	private let configureFuture:Future<Future<Result<any Sendable, any Swift.Error>, Never>, Never>
	/// the future that will be set after the work result is returned.
	private let returnFuture:Future<Result<any Sendable, any Swift.Error>, Never>

	// call this from within the pthread. this will initialize the workspace for the work that is about to begin on the pthread.
	fileprivate init(
		_ setup:Setup
	) {
		workspaceInstance = setup.thread_worktype.init(setup.containedArg)
		workspaceType = setup.thread_worktype
		configureFuture = setup.configureFuture
		returnFuture = setup.thread_worktype.buildReturnFuture()
	}

	// assign cancellation values to the relevant futures.
	fileprivate func setCancellation() {
		// set the return future to a failure error that is aproprate for cancellation.
		_ = try? returnFuture.cancel()		// this try may fail because its theoretically possible that the work returns an instant moment before this is called.

		_ = try? configureFuture.cancel()	// this may not fail because its presumed that if configureFuture is not already nil, then it is a valid future that must be set.
	}

	// set the configuration future to success.
	private func setSuccessfulConfiguration() {
		// set the configure future to success.
		try! configureFuture.setSuccess(returnFuture)
	}

	// run the work and have it pass the result into the return future.
	fileprivate mutating func work() {
		// set the configuration future to success.
		setSuccessfulConfiguration()

		// run the work and have it pass the result into the return future. in a successful case, this will pass a retained instance of Contained<ReturnType> into the return future.
		workspaceInstance.firePThreadWork(into:returnFuture)
	}
}

// assistive structure to define how a pthread shall be launched and ran.
fileprivate struct Setup {
	// a pointer to the contained argument
	fileprivate let containedArg:any Sendable
	// a pthread takes time to launch and configure itself before we can allow it to be canceled. this future will be set to success when the pthread is ready to be canceled.
	fileprivate let configureFuture:Future<Future<Result<any Sendable, any Swift.Error>, Never>, Never>
	// the type of pthread work to execute. this informs the pthread launch what kind of memory and work needs to be done.
	fileprivate let thread_worktype:any PThreadWork.Type

	// call this from outside the pthread before it is launched. this setup structure will initialize on the heap and passed into the pthread from there.
	fileprivate init<P>(
		_ _:P.Type,
		containedArgument:any Sendable,
		configureFuture:Future<Future<Result<any Sendable, any Swift.Error>, Never>, Never>
	) where P:PThreadWork {
		self.containedArg = containedArgument
		self.thread_worktype = P.self
		self.configureFuture = configureFuture
	}
}

/// the various states that a running pthread can be in as it goes about its lifecycle as a launched thread.
fileprivate enum CloseOut:UInt8, AtomicRepresentable {
	/// the pthread is running.
	case threadRunning = 0
	/// the pthread is cancelled but not yet exited.
	case threadCancelled = 1
	/// the pthread is exited.
	case threadExited = 2
	/// the pthread is joining.
	case threadJoining = 3
	/// the pthread is joined.
	case threadJoined = 4
}

/// a Sendable class that encompasses a running pthread. this structure is responsible for ensuring that the pthread is joined and that the memory is properly managed between the running memory space and the calling memory space.
public final class Running<W>:@unchecked Sendable where W:PThreadWork {

	private struct State:Sendable {
		internal var closeOut:CloseOut = .threadRunning
	}

	// the pthread primitive
	internal let ptp:__cswiftslash_threads_t_type
	private let returnFuture:Future<Result<any Sendable, any Swift.Error>, Never>
	private let operatingState:Mutex<State> = Mutex(State())

	fileprivate init(
		alreadyLaunched pthread:consuming __cswiftslash_threads_t_type,
		returnFuture rf:consuming Future<Result<any Sendable, any Swift.Error>, Never>
	) {
		ptp = pthread
		returnFuture = rf
		rf.whenResult { [weak self] resultPtr in
			guard let self = self else {
				return
			}
			operatingState.withLock({ stateAccess in
				// the goal here is to update the state is at least at the "exited" stage at this point.
				switch stateAccess.closeOut {
					case .threadRunning:
						stateAccess.closeOut = .threadExited
					case .threadCancelled:
						// the thread has been cancelled. we need to wait for it to exit.
						stateAccess.closeOut = .threadExited
					default:
						// the thread has already exited or is joining or joined. we need to do nothing.
						break
				}
			})
		}
	}

	/// async block for the work to be done on the pthread. throws a designated cancellation error if the task is canceled. the pthread is not cancelled when the task is canceled.
	public borrowing func workResult<E>(throwingOnCurrentTaskCancellation _:E.Type, taskCancellationError makeError:@autoclosure () -> E) async throws(E) -> Result<W.ReturnType, W.ThrowType>? where E:Swift.Error {
		let result = try await returnFuture.result(throwing:E.self, onCurrentTaskCancellation:makeError())
		guard result != nil else {
			return nil
		}
		switch result!.get() {
			case .success(let value):
				return .success(value as! W.ReturnType)
			case .failure(let error):
				return .failure(error as! W.ThrowType)
		}
	}

	/// async block for the work to be done on the pthread. does not throw any error when the current task is cancelled. the pthread is not cancelled when the task is canceled.
	public borrowing func workResult(throwingOnCurrentTaskCancellation _:Never.Type = Never.self) async -> Result<W.ReturnType, W.ThrowType>? {
		let result = await returnFuture.result(throwing:Never.self, onCurrentTaskCancellation:fatalError("SwiftSlashPThread: pthread work result was cancelled. this is a critical error. \(#file):\(#line)"))
		guard result != nil else {
			return nil
		}
		switch result!.get() {
			case .success(let value):
				return .success(value as! W.ReturnType)
			case .failure(let error):
				return .failure(error as! W.ThrowType)
		}
	}

	/// cancels the running pthread. it will exit when it reaches the next pthread cancellation point.
	/// - returns: true if the pthread was successfully set to cancelled, false if the pthread was not successfully canceled.
	public borrowing func cancel() throws(PThreadCancellationFailure) {
		try operatingState.withLock({ stateAccess throws(PThreadCancellationFailure) in
			switch stateAccess.closeOut {
				case .threadRunning:
					guard pthread_cancel(ptp) == 0 else {
						throw .internalFailure
					}
					stateAccess.closeOut = .threadCancelled
				case .threadCancelled:
					throw PThreadCancellationFailure.alreadyCancelled
				case .threadExited:
					throw PThreadCancellationFailure.alreadyCancelled
				case .threadJoining:
					throw PThreadCancellationFailure.alreadyCancelled
				case .threadJoined:
					throw PThreadCancellationFailure.alreadyCancelled
			}
		})
	}

	@available(*, noasync, message:"function joinSync() is not async safe. it is only safe to call this function from the main thread.")
	public consuming func joinSync() throws(PThreadJoinFailure) {
		try operatingState.withLock({ stateAccess throws(PThreadJoinFailure) in
			guard stateAccess.closeOut != .threadJoined && stateAccess.closeOut != .threadJoining else {
				throw PThreadJoinFailure()
			}
			stateAccess.closeOut = .threadJoining
		})
		guard pthread_join(ptp, nil) == 0 else {
			throw PThreadJoinFailure()
		}
		try operatingState.withLock({ stateAccess throws(PThreadJoinFailure) in
			stateAccess.closeOut = .threadJoined
		})
	}

	deinit {
		switch operatingState.withLock({ stateAccess in
			return stateAccess.closeOut
		}) {
			case .threadRunning:
				// the thread is still running. we need to cancel it.
				try! cancel()
				// wait for the thread to exit.
				try! joinSync()
			case .threadCancelled:
				// the thread has been cancelled. we need to wait for it to exit.
				try! joinSync()
			case .threadExited:
				// the thread has exited. we need to wait for it to exit.
				try! joinSync()
			case .threadJoined:
				break
			case .threadJoining:
				break;
		}
	}
}

/// primary pthread wrap implementation. this is the primary way that the pthread is launched and ran in a fully memory-safe way with Swift.
/// - parameter work: the type of work that is being done on the pthread.
/// - parameter argument: the argument that is being passed into the work function.
/// - returns: the running pthread that is being launched.
/// - throws: a LaunchFailure error if the pthread fails to launch.
@available(*, noasync, message:"this function launches a pthread and waits for the pthread to begin working. this requires blocking, which is not allowed in swift async code.")
fileprivate func launchPThread<W, A>(work _:W.Type, argument:A) -> Result<Running<W>, PThreadLaunchFailure> where W:PThreadWork, W.ArgumentType == A {
	// this is the future that represents a successful launch and configuration of a pthread. pthreads must be configured for proper handling of cancellation in order to not leak memory.
	let configureFuture = Future<Future<Result<any Sendable, any Swift.Error>, Never>, Never>()

	// define the memoryspace where we will store the setup structure for the pthread.
	let launchStructure = UnsafeMutablePointer<Setup>.allocate(capacity:1)

	launchStructure.initialize(to:Setup(W.self, containedArgument:argument, configureFuture:configureFuture))
	defer {
		launchStructure.deinitialize(count:1)
		launchStructure.deallocate()
	}

	// launch the pthread, verify the results are successful.
	var launchResult:Int32 = -1
	let pthr = __cswiftslash_threads_config_run(
		__cswiftslash_threads_config_init(
			launchStructure,
			_run_alloc,
			_run_main,
			_run_cancel,
			_run_dealloc
		),
		&launchResult
	)
	guard launchResult == 0 else {
		// throw a launch failure error.
		return .failure(PThreadLaunchFailure())
	}

	// wait for the pthread to be configured and ready to be canceled.
	let returnFuture = configureFuture.waitSynchronously().wait()!.get()
	return .success(Running(alreadyLaunched:pthr, returnFuture:returnFuture))
}

// below are the four "pillar functions" that allow for seamless and tightly integrated pthread tasks.
/// allocator function. responsible for initializing the workspace and transferring the crucial memory from the Setup.
@c fileprivate func _run_alloc(_ csPtr:__cswiftslash_ptr_t) -> __cswiftslash_ptr_t {
	let ws = UnsafeMutablePointer<Workspace>.allocate(capacity:1)
	ws.initialize(to:Workspace(csPtr.assumingMemoryBound(to:Setup.self).pointee))
	return UnsafeMutableRawPointer(ws)
}
/// deallocator function. responsible for being as intentional as possible in capturing the current workspace and releasing the reference of it before it returns.
@c fileprivate func _run_dealloc(_ wsPtr:__cswiftslash_ptr_t) -> Void {
	wsPtr.assumingMemoryBound(to:Workspace.self).deinitialize(count:1).deallocate()
}
/// cancel function. responsible for setting the cancellation flag on the contained workspace.
@c fileprivate func _run_cancel(_ wsPtr:__cswiftslash_ptr_t) -> Void {
	wsPtr.assumingMemoryBound(to:Workspace.self).pointee.setCancellation()
}
/// main function. responsible for running the work function and setting the result into the return future.
@c fileprivate func _run_main(_ wsPtr:__cswiftslash_ptr_t) -> Void { 
	// capture the contained workspace (nonretained because of pthread cancellation) so that we can interact with it safely for the work.
	wsPtr.assumingMemoryBound(to:Workspace.self).pointee.work()
}