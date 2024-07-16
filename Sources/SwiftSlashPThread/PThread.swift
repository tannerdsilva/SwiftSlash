import __cswiftslash
import SwiftSlashFuture
import SwiftSlashContained

/// thrown when a pthread cannot be created.
internal struct LaunchError:Swift.Error {}

/// thrown when a pthread is unable to be canceled.
internal struct CancellationError:Swift.Error {}


public struct GeneralPThreadWorker<R>:PThreadWorkspace {
	public typealias Argument = @Sendable () throws -> R
	public typealias ReturnType = R

	public let argument:Argument

	public init(_ argument:@escaping Argument) {
		self.argument = argument
	}

	public mutating func run() throws -> R {
		return try self.argument()
	}
}

extension PThreadWorkspace {
	internal static func run(_ arg:Argument) async throws -> ReturnType {
		let launchedPThread = try await launchPThread(Self.self, argument:arg)
		return try await withTaskCancellationHandler(operation: {
			return Unmanaged<Contained<ReturnType>>.fromOpaque(try await launchedPThread.get()!).takeRetainedValue().consumeValue()
		}, onCancel: {
			try! launchedPThread.cancel()
		})
	}
}

extension PThreadWorkspace {
	// this is a bridge function that allows the c code to call the allocator function for the specific type in question. this is a critical step in the pthread lifecycle because this is where the initial argument is consumed.
	fileprivate init(_ ptr:UnsafeMutableRawPointer) {
		self.init(Unmanaged<Contained<Argument>>.fromOpaque(ptr).takeRetainedValue().consumeValue())
	}
	// this is a convenience and bridge function that allows the contained workspace to run the work function and set the result into the return future. the pointer pass in success to the future is presumed to be a retained instance of Contained<ReturnType>
	fileprivate mutating func run(future:borrowing Future<UnsafeMutableRawPointer>) {
		let op:UnsafeMutableRawPointer
		do {
			op = Unmanaged.passRetained(Contained(try run())).toOpaque()
		} catch let error {
			try! future.setFailure(error)
			return
		}
		try? future.setSuccess(op) // this is allowed to fail because the future may have been canceled at the instant before this is called.
	}
	// this is a bridge function that allows the contained workspace to obtain a future that knows how to deallocate the result when the future is destroyed.
	fileprivate static func makeContainedReturnFuture() -> Future<UnsafeMutableRawPointer> {
		return Future<UnsafeMutableRawPointer>(successfulResultDeallocator: { ptr in
			_ = Unmanaged<Contained<ReturnType>>.fromOpaque(ptr).takeRetainedValue()
		})
	}
}

/// represents the memory space that is initialized and used within a pthread to accomplish a task.
fileprivate final class ContainedWorkspace {
	
	/// the instance of the workspace that is being used in the pthread.
	private var workspaceInstance:any PThreadWorkspace
	
	/// the type of workspace that is being used in the pthread.
	private let workspaceType:any PThreadWorkspace.Type

	/// the future for pthread configuration. this is set to success when the pthread is configured, running its work, and ready to be canceled. after a result is passed into the return future, this future is set to nil.
	private var configureFuture:Future<Future<UnsafeMutableRawPointer>>?
	private let returnFuture:Future<UnsafeMutableRawPointer>

	// call this from within the pthread. this will initialize the workspace for the work that is about to begin on the pthread.
	fileprivate init(
		_ setup:UnsafeMutablePointer<PThreadSetup>
	) {
		self.workspaceInstance = setup.pointer(to:\.thread_worktype)!.pointee.init(setup.pointer(to:\.containedArg)!.pointee)
		self.workspaceType = setup.pointer(to:\.thread_worktype)!.pointee
		self.configureFuture = setup.pointer(to:\.configureFuture)!.pointee
		self.returnFuture = setup.pointer(to:\.thread_worktype)!.pointee.makeContainedReturnFuture()
		
		setup.pointee.pthread_config.deinitialize(count:1).deallocate()
		setup.deinitialize(count:1).deallocate()
	}

	fileprivate borrowing func setCancellation() {
		// set the return future to a failure error that is aproprate for cancellation.
		try? returnFuture.setFailure(CancellationError()) // this try may fail because its theoretically possible that the work returns an instant moment before this is called.

		try! configureFuture?.setFailure(CancellationError()) // this may not fail because its presumed that if configureFuture is not already nil, then it is a valid future that must be set.
		configureFuture = nil
	}

	private borrowing func setSuccessfulConfiguration() {
		// set the configure future to success.
		try! configureFuture?.setSuccess(returnFuture) // this may not fail because its presumed that if configureFuture is not already nil, then it is a valid future that must be set.
		configureFuture = nil
	}

	fileprivate borrowing func work() {
		// set the configuration future to success.
		setSuccessfulConfiguration()

		// run the work and have it pass the result into the return future. in a successful case, this will pass a retained instance of Contained<ReturnType> into the return future.
		workspaceInstance.run(future:returnFuture)
	}
}

// assistive structure to define how a pthread shall be launched and ran.
fileprivate struct PThreadSetup {
	// a pointer to the contained argument
	fileprivate let containedArg:UnsafeMutableRawPointer

	// a pthread takes time to launch and configure itself before we can allow it to be canceled. this future will be set to success when the pthread is ready to be canceled.
	fileprivate var configureFuture:Future<Future<UnsafeMutableRawPointer>> = Future<Future<UnsafeMutableRawPointer>>()

	// the type of pthread work to execute. this informs the pthread launch what kind of memory and work needs to be done.
	fileprivate let thread_worktype:any PThreadWorkspace.Type

	// the pthread configuration that is used to launch the pthread.
	fileprivate let pthread_config = UnsafeMutablePointer<_cswiftslash_pthread_config_t>.allocate(capacity:1)

	fileprivate init<P>(_ workType:P.Type, containedArgument:UnsafeMutableRawPointer) where P:PThreadWorkspace {
		self.containedArg = containedArgument
		self.thread_worktype = P.self
	}
}

// this function makes three allocations. if the pthread is successfully launched, none of the memory needs to be deallocated. if the pthread fails to launch, the memory will be deallocated before the function throws.
fileprivate func launchPThread<W, A>(_ workType:W.Type, argument:A) async throws -> RunningPThread where W:PThreadWorkspace, W.Argument == A {
	// allocate the memory where the pthread will be configured.
	let allocPrivate = UnsafeMutablePointer<PThreadSetup>.allocate(capacity:1)

	// initialize the floating setup to the consumed argument value.
	allocPrivate.initialize(to:PThreadSetup(workType, containedArgument:Unmanaged.passRetained(Contained(argument)).toOpaque()))

	// initialize the pthread config onto the setup structure. argument pointer passed for allocator will be allocPrivate
	allocPrivate.pointee.pthread_config.initialize(to:_cswiftslash_pthread_config_init(
		allocPrivate,
		_run_alloc,
		_run_main,
		_run_cancel,
		_run_dealloc
	));

	// take a local copy of the configure future so that we can await it later.
	let configFuture = allocPrivate.pointee.configureFuture

	// launch the pthread, verify the results are successful.
	var launchResult:Int32 = -1
	let pthr = _cswiftslash_pthread_config_run(allocPrivate.pointee.pthread_config, &launchResult)
	guard launchResult == 0 else {
		
		// balance the retained value that was passed into the pthread setup.
		_ = Unmanaged<Contained<A>>.fromOpaque(allocPrivate.pointee.containedArg).takeRetainedValue()

		// deinitialize and deallocate the setup structure.
		allocPrivate.pointee.pthread_config.deinitialize(count:1).deallocate()
		allocPrivate.deinitialize(count:1).deallocate()

		throw LaunchError()
	}

	// wait for the pthread to configure itself. at this point we can return the RunningPThread object through the future but we cant do so until the pthread is ready to be canceled. this is what we wait for.
	let returnFuture = try await configFuture.get()
	return RunningPThread(pthr, future:returnFuture, type:workType)
}

// allocator function. responsible for initializing the workspace and transferring the crucial memory from the pthreadsetup.
fileprivate let _run_alloc:@convention(c) (_cswiftslash_ptr_t) -> _cswiftslash_ptr_t = { csPtr in
	return Unmanaged<ContainedWorkspace>.passRetained(
		ContainedWorkspace(
			csPtr.assumingMemoryBound(to:PThreadSetup.self)
		)
	).toOpaque()
}
// deallocator function. responsible for being as intentional as possible in capturing the current workspace and releasing the reference of it before it returns.
fileprivate let _run_dealloc:@convention(c) (_cswiftslash_ptr_t) -> Void = { wsPtr in
	var ws:ContainedWorkspace? = Unmanaged<ContainedWorkspace>.fromOpaque(wsPtr).takeRetainedValue()
	ws = nil
}
// cancel function. responsible for setting the cancellation flag on the contained workspace.
fileprivate let _run_cancel:@convention(c) (_cswiftslash_ptr_t) -> Void = { wsPtr in
	Unmanaged<ContainedWorkspace>.fromOpaque(wsPtr).takeUnretainedValue().setCancellation()
}
// main function. responsible for running the work function and setting the result into the return future.
fileprivate let _run_main:@convention(c) (_cswiftslash_ptr_t) -> Void = { wsPtr in
	// capture the contained workspace (nonretained because of pthread cancellation) so that we can interact with it safely for the work.
	Unmanaged<ContainedWorkspace>.fromOpaque(wsPtr).takeUnretainedValue().work()
}