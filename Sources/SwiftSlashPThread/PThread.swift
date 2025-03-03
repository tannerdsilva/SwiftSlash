/*
LICENSE MIT
copyright (c) tanner silva 2025. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import __cswiftslash_threads
import SwiftSlashFuture
import SwiftSlashContained
import Synchronization

// this file articulates a lot of unsafe and unbalanced memory management. the scope of the unsafety is limited to this single file, therefore, any possible errors or mishandlings of the memory should be visible from this file alone. the file consists of mostly private and fileprivate functions, with only a small handful of public/internal entrypoints being provided.

/// runs any given arbitrary function on a newly created pthread.
public func run<R>(_ work:consuming @escaping @Sendable () throws -> R) async throws(PThreadLaunchFailure) -> Result<R, Swift.Error>? where R:Sendable {
	let launchedThread = try await GenericPThread.launch(work)
	return await launchedThread.workResult()
}

/// launch a pthread with a given function and return the running pthread.
public func launch<R>(_ work:consuming @escaping @Sendable () throws -> R) async throws(PThreadLaunchFailure) -> Running<GenericPThread<R>> where R:Sendable {
	return try await GenericPThread.launch(work)
}

extension PThreadWork {
	public static func launch(_ arg:consuming Argument) async throws(PThreadLaunchFailure) -> Running<Self> {
		return try await launchPThread(work:Self.self, argument:arg)
	}
	public static func run(_ arg:consuming Argument) async throws -> Result<ReturnType, ThrowType>? {
		let launched = try await Self.launch(arg)
		return try await launched.workResult(throwingOnCurrentTaskCancellation:CancellationError.self, taskCancellationError:CancellationError())
	}
}

extension PThreadWork {
	// this is a bridge function that allows the c code to call the allocator function for the specific type in question. this is a critical step in the pthread lifecycle because this is where the initial argument is consumed.
	fileprivate init(_ ptr:UnsafeMutableRawPointer) {
		self = Self(Unmanaged<Contained<Argument>>.fromOpaque(ptr).takeRetainedValue().value())
	}
	// this is a bridge function that allows the primary work implementation to run and return into the future as it needs to when it is called from the pthread.
	fileprivate mutating func firePThreadWork(into future:consuming Future<UnsafeMutableRawPointer, Never>) {
		let result:Result<ReturnType, ThrowType>
		do {
			let retVal = try pthreadWork()
			result = .success(retVal)
		} catch let error {
			result = .failure(error)
		}
		let retainedValue = Unmanaged.passRetained(Contained(result)).toOpaque()
		try! future.setSuccess(retainedValue)		
	}
	// builds the strictly typed future with deallocator function that the pthread worker will use.
	fileprivate static func buildReturnFuture() -> Future<UnsafeMutableRawPointer, Never> {
		return Future<UnsafeMutableRawPointer, Never>(successfulResultDeallocator: { ptr in
			_ = Unmanaged<Contained<Result<ReturnType, ThrowType>>>.fromOpaque(ptr).takeRetainedValue()
		})
	}
}

/// represents the memory space that is initialized and used within a pthread to accomplish a task.
fileprivate struct Workspace {
	
	/// the instance of the workspace that is being used in the pthread.
	private var workspaceInstance:any PThreadWork
	/// the type of workspace that is being used in the pthread.
	private let workspaceType:any PThreadWork.Type
	/// the future for pthread configuration. this is set to success when the pthread is configured, running its work, and ready to be canceled. after a result is passed into the return future, this future is set to nil.
	private let configureFuture:Future<UnsafeMutableRawPointer, Never>
	/// the future that will be set after the work result is returned.
	private let returnFuture:Future<UnsafeMutableRawPointer, Never>

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
		try? returnFuture.cancel()		// this try may fail because its theoretically possible that the work returns an instant moment before this is called.

		try? configureFuture.cancel()	// this may not fail because its presumed that if configureFuture is not already nil, then it is a valid future that must be set.
	}

	// set the configuration future to success.
	private func setSuccessfulConfiguration() {
		// set the configure future to success.
		try! configureFuture.setSuccess(Unmanaged.passRetained(returnFuture).toOpaque())
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
	fileprivate let containedArg:UnsafeMutableRawPointer

	// a pthread takes time to launch and configure itself before we can allow it to be canceled. this future will be set to success when the pthread is ready to be canceled.
	fileprivate let configureFuture:Future<UnsafeMutableRawPointer, Never>

	// the type of pthread work to execute. this informs the pthread launch what kind of memory and work needs to be done.
	fileprivate let thread_worktype:any PThreadWork.Type

	// call this from outside the pthread before it is launched. this setup structure will initialize on the heap and passed into the pthread from there.
	fileprivate init<P>(
		_ workType:P.Type,
		containedArgument:UnsafeMutableRawPointer,
		configureFuture:Future<UnsafeMutableRawPointer, Never>
	) where P:PThreadWork {
		self.containedArg = containedArgument
		self.thread_worktype = P.self
		self.configureFuture = configureFuture
	}
}

/// a noncopyable structure that safely handles a running pthread. this structure is responsible for ensuring that the pthread is joined and that the memory is properly managed between the running memory space and the calling memory space.
public final class Running<W>:@unchecked Sendable where W:PThreadWork {
	// the pthread primitive
	fileprivate let ptp:__cswiftslash_threads_t_type
	// the future that will be set to success when the pthread is launched.
	fileprivate let returnFuture:Future<UnsafeMutableRawPointer, Never>
	// the atomic flag that indicates if the pthread is running or not.
	fileprivate let isRunning:Atomic<Bool> = .init(true)

	fileprivate init(
		alreadyLaunched pthread:__cswiftslash_threads_t_type,
		returnFuture rf:consuming Future<UnsafeMutableRawPointer, Never>
	) {
		ptp = pthread
		returnFuture = rf
		returnFuture.whenResult { [weak self] res in
			self?.isRunning.store(false, ordering:.releasing)
		}
	}

	/// async block for the work to be done on the pthread. throws a designated cancellation error if the task is canceled. the pthread is not cancelled when the task is canceled.
	public borrowing func workResult<E>(throwingOnCurrentTaskCancellation throwType:consuming E.Type, taskCancellationError makeError:@autoclosure () -> E) async throws(E) -> Result<W.ReturnType, W.ThrowType>? where E:Swift.Error {
		let result = try await returnFuture.result(throwingOnCurrentTaskCancellation:E.self, taskCancellationError:makeError())
		guard result != nil else {
			return nil
		}
		let returnResult = Unmanaged<Contained<Result<W.ReturnType, W.ThrowType>>>.fromOpaque(result!.get()).takeUnretainedValue().value()
		return returnResult
	}

	/// async block for the work to be done on the pthread. does not throw any error when the current task is cancelled. the pthread is not cancelled when the task is canceled.
	public borrowing func workResult(throwingOnCurrentTaskCancellation:Never.Type = Never.self) async -> Result<W.ReturnType, W.ThrowType>? {
		let result = await returnFuture.result(throwingOnCurrentTaskCancellation:Never.self)
		guard result != nil else {
			return nil
		}
		let returnResult = Unmanaged<Contained<Result<W.ReturnType, W.ThrowType>>>.fromOpaque(result!.get()).takeUnretainedValue().value()
		return returnResult
	}

	/// cancels the running pthread. it will exit when it reaches the next pthread cancellation point.
	/// - returns: true if the pthread was successfully set to cancelled, false if the pthread was not successfully canceled.
	public borrowing func cancel() throws(PThreadCancellationFailure) {
		guard pthread_cancel(ptp) == 0 else {
			throw PThreadCancellationFailure.systemError
		}
	}

	deinit {
		if isRunning.load(ordering:.acquiring) {
			// set the cancellation flag on the pthread.
			do {
				_ = try cancel()
			} catch {
				fatalError("SwiftSlashPThread: pthread cancellation failed. this is a critical error. \(#file):\(#line)")
			}
		}

		// join the pthread
		guard pthread_join(ptp, nil) == 0 else {
			fatalError("SwiftSlashPThread: pthread_join failed. this is a critical error. \(#file):\(#line)")
		}
	}
}

/// primary pthread wrap implementation. this is the primary way that the pthread is launched and ran in a fully memory-safe way with Swift.
/// - parameter work: the type of work that is being done on the pthread.
/// - parameter argument: the argument that is being passed into the work function.
/// - returns: the running pthread that is being launched.
/// - throws: a LaunchFailure error if the pthread fails to launch.
fileprivate func launchPThread<W, A>(work workType:W.Type, argument:A) async throws(PThreadLaunchFailure) -> Running<W> where W:PThreadWork, W.Argument == A {
	// this is the future that represents a successful launch and configuration of a pthread. pthreads must be configured for proper handling of cancellation in order to not leak memory.
	let configureFuture = Future<UnsafeMutableRawPointer, Never>(successfulResultDeallocator: { ptr in
		// free the retained future from memory.
		_ = Unmanaged<Future<UnsafeMutableRawPointer, Never>>.fromOpaque(ptr).takeRetainedValue()
	})

	// define the memoryspace where we will store the setup structure for the pthread.
	let launchStructure = UnsafeMutablePointer<Setup>.allocate(capacity:1)
	launchStructure.initialize(to:Setup(workType, containedArgument:Unmanaged.passRetained(Contained(argument)).toOpaque(), configureFuture:configureFuture))
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
		// balance the retained value that was passed into the pthread setup but not used due to the pthread launch failure.
		_ = Unmanaged<Contained<A>>.fromOpaque(launchStructure.pointee.containedArg).takeRetainedValue()
		// throw a launch failure error.
		throw PThreadLaunchFailure()
	}

	// wait for the pthread to be configured and ready to be canceled.
	let returnFutureOpaque = await configureFuture.result()!.get()
	let returnFuture = Unmanaged<Future<UnsafeMutableRawPointer, Never>>.fromOpaque(returnFutureOpaque).takeUnretainedValue()
	return Running(alreadyLaunched:pthr, returnFuture:returnFuture)
}

// allocator function. responsible for initializing the workspace and transferring the crucial memory from the Setup.
fileprivate let _run_alloc:@convention(c) (__cswiftslash_ptr_t) -> __cswiftslash_ptr_t = { csPtr in
	let ws = UnsafeMutablePointer<Workspace>.allocate(capacity:1)
	ws.initialize(to:Workspace(csPtr.assumingMemoryBound(to:Setup.self).pointee))
	return UnsafeMutableRawPointer(ws)
}
// deallocator function. responsible for being as intentional as possible in capturing the current workspace and releasing the reference of it before it returns.
fileprivate let _run_dealloc:@convention(c) (__cswiftslash_ptr_t) -> Void = { wsPtr in
	wsPtr.assumingMemoryBound(to:Workspace.self).deinitialize(count:1).deallocate()
}
// cancel function. responsible for setting the cancellation flag on the contained workspace.
fileprivate let _run_cancel:@convention(c) (__cswiftslash_ptr_t) -> Void = { wsPtr in
	wsPtr.assumingMemoryBound(to:Workspace.self).pointee.setCancellation()
}
// main function. responsible for running the work function and setting the result into the return future.
fileprivate let _run_main:@convention(c) (__cswiftslash_ptr_t) -> Void = { wsPtr in
	// capture the contained workspace (nonretained because of pthread cancellation) so that we can interact with it safely for the work.
	wsPtr.assumingMemoryBound(to:Workspace.self).pointee.work()
}