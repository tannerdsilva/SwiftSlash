
// this file articulates a lot of unsafe and unbalanced memory management. the scope of the unsafety is limited to this single file, therefore, any possible errors or mishandlings of the memory should be visible from this file alone. the file consists of mostly private and fileprivate functions, with only a small handful of public/internal entrypoints being provided.

import __cswiftslash
import SwiftSlashFuture
import SwiftSlashContained

/// launches a pthread that will run the given work function and return the result.
public func launch<R>(_ work:consuming @escaping () throws -> R) async throws -> Running<R> {
	let launchedPThread = try await _launch(GenericPThread<R>.self, argument:work)
	return Running(alreadyLaunched:launchedPThread)
}

/// runs any given arbitrary function on a pthread.
public func run<R>(_ work:consuming @escaping () throws -> R) async throws -> Result<R, Swift.Error> {
	let launchedThread = try await GenericPThread.launch(work)
	return try await launchedThread.result()
}

extension PThreadWork {
	public static func launch(_ arg:consuming Argument) async throws -> Running<ReturnType> {
		let running = try await _launch(Self.self, argument:arg)
		return Running(alreadyLaunched:running)
	}
	public static func run(_ arg:consuming Argument) async throws -> Result<ReturnType, Swift.Error> {
		let launched = try await Self.launch(arg)
		return try await launched.result()
	}
}

extension PThreadWork {
	// this is a bridge function that allows the c code to call the allocator function for the specific type in question. this is a critical step in the pthread lifecycle because this is where the initial argument is consumed.
	fileprivate init(_ ptr:UnsafeMutableRawPointer) {
		self = Self(Unmanaged<Contained<Argument>>.fromOpaque(ptr).takeRetainedValue().value())
	}
	// this is a bridge function that allows the primary work implementation to run and return into the future as it needs to when it is called from the pthread.
	fileprivate mutating func run(future:borrowing Future<UnsafeMutableRawPointer>) {
		let op:UnsafeMutableRawPointer
		do {
			op = Unmanaged.passRetained(Contained(try pthreadWork())).toOpaque()
		} catch let error {
			try! future.setFailure(error)
			return
		}
		try! future.setSuccess(op) // this is allowed to fail because the future may have been canceled at the instant before this is called.
	}
	fileprivate func configureNewReturnFuture() -> Future<UnsafeMutableRawPointer> {
		return Future<UnsafeMutableRawPointer>(successfulResultDeallocator: { ptr in
			_ = Unmanaged<Contained<ReturnType>>.fromOpaque(ptr).takeRetainedValue()
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
	private var configureFuture:Future<Future<UnsafeMutableRawPointer>>

	/// the future that will be set after the work result is returned.
	private let returnFuture:Future<UnsafeMutableRawPointer>

	// call this from within the pthread. this will initialize the workspace for the work that is about to begin on the pthread.
	fileprivate init(
		_ setup:Setup
	) {
		workspaceInstance = setup.thread_worktype.init(setup.containedArg)
		workspaceType = setup.thread_worktype
		configureFuture = setup.configureFuture
		returnFuture = workspaceInstance.configureNewReturnFuture()
	}

	// assign cancellation values to the relevant futures.
	fileprivate func setCancellation() {
		// set the return future to a failure error that is aproprate for cancellation.
		try? returnFuture.setFailure(CancellationError())		// this try may fail because its theoretically possible that the work returns an instant moment before this is called.

		try? configureFuture.setFailure(CancellationError())	// this may not fail because its presumed that if configureFuture is not already nil, then it is a valid future that must be set.
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
		workspaceInstance.run(future:returnFuture)
	}
}

// assistive structure to define how a pthread shall be launched and ran.
fileprivate struct Setup {
	// a pointer to the contained argument
	fileprivate let containedArg:UnsafeMutableRawPointer

	// a pthread takes time to launch and configure itself before we can allow it to be canceled. this future will be set to success when the pthread is ready to be canceled.
	fileprivate var configureFuture:Future<Future<UnsafeMutableRawPointer>>

	// the type of pthread work to execute. this informs the pthread launch what kind of memory and work needs to be done.
	fileprivate let thread_worktype:any PThreadWork.Type

	// call this from outside the pthread before it is launched. this setup structure will initialize on the heap and passed into the pthread from there.
	fileprivate init<P>(
		_ workType:P.Type,
		containedArgument:UnsafeMutableRawPointer,
		configureFuture:Future<Future<UnsafeMutableRawPointer>>
	) where P:PThreadWork {
		self.containedArg = containedArgument
		self.thread_worktype = P.self
		self.configureFuture = configureFuture
	}
}

// this function makes three allocations. if the pthread is successfully launched, none of the memory needs to be deallocated. if the pthread fails to launch, the memory will be deallocated before the function throws.
fileprivate func _launch<W, A>(_ workType:W.Type, argument:consuming A) async throws -> Launched where W:PThreadWork, W.Argument == A {
	// the primary role of this function is to manage the intersection between the calling memoryspace and the launched memoryspace. this configuration future is the primary way these two memoryspaces coordinate the timing of their memory allocations and freeing.
	let configureFuture = Future<Future<UnsafeMutableRawPointer>>()

	// the configuring memory for the pthread is necessarily1 floated in the heap since addressing this memory directly from the "stack" creates issues when the await is called towards the end of the function.
	let launchStructure = UnsafeMutablePointer<Setup>.allocate(capacity:1)
	launchStructure.initialize(to:Setup(workType, containedArgument:Unmanaged.passRetained(Contained(argument)).toOpaque(), configureFuture:configureFuture))
	defer {
		launchStructure.deinitialize(count:1)
		launchStructure.deallocate()
	}

	// launch the pthread, verify the results are successful.
	var launchResult:Int32 = -1
	let pthr = _cswiftslash_pthread_config_run(
		_cswiftslash_pthread_config_init(
			launchStructure,
			_run_alloc,
			_run_main,
			_run_cancel,
			_run_dealloc
		),
		&launchResult
	)
	guard launchResult == 0 else {
		// balance the retained value that was passed into the pthread setup.
		_ = Unmanaged<Contained<A>>.fromOpaque(launchStructure.pointee.containedArg).takeRetainedValue()
		throw LaunchFailure()
	}

	// wait for the pthread to configure itself. at this point we can return the RunningPThread object through the future but we cant do so until the pthread is ready to be canceled. this is what we wait for.
	let returnFuture = try await configureFuture.get()
	return Launched(pthr, future:returnFuture)
}

// allocator function. responsible for initializing the workspace and transferring the crucial memory from the Setup.
fileprivate let _run_alloc:@convention(c) (_cswiftslash_ptr_t) -> _cswiftslash_ptr_t = { csPtr in
	let setup = UnsafeMutablePointer<Workspace>.allocate(capacity:1)
	setup.initialize(to:Workspace(csPtr.assumingMemoryBound(to:Setup.self).pointee))
	return UnsafeMutableRawPointer(setup)
}
// deallocator function. responsible for being as intentional as possible in capturing the current workspace and releasing the reference of it before it returns.
fileprivate let _run_dealloc:@convention(c) (_cswiftslash_ptr_t) -> Void = { wsPtr in
	wsPtr.assumingMemoryBound(to:Workspace.self).deinitialize(count:1).deallocate()
}
// cancel function. responsible for setting the cancellation flag on the contained workspace.
fileprivate let _run_cancel:@convention(c) (_cswiftslash_ptr_t) -> Void = { wsPtr in
	wsPtr.assumingMemoryBound(to:Workspace.self).pointee.setCancellation()
}
// main function. responsible for running the work function and setting the result into the return future.
fileprivate let _run_main:@convention(c) (_cswiftslash_ptr_t) -> Void = { wsPtr in
	// capture the contained workspace (nonretained because of pthread cancellation) so that we can interact with it safely for the work.
	wsPtr.assumingMemoryBound(to:Workspace.self).pointee.work()
}