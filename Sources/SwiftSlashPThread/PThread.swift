import __cswiftslash
import SwiftSlashFuture
import SwiftSlashContained

#if SWIFTSLASH_SHOULDLOG
import Logging
#endif

/// thrown when a pthread cannot be created.
internal struct LaunchFailure:Swift.Error {}

/// thrown when a pthread is unable to be canceled.
internal struct CancellationFailure:Swift.Error {}

internal struct PThreadFuncRunner<R>:PThreadWork {
	// /// work that needs to run on the pthread.
	// internal struct Func {
	// 	/// the argument that is passed into the work function.
	// 	typealias WorkFuncType = (consuming A) throws -> R

	// 	/// the argument that is passed into the work function.
	// 	private let argument:A

	// 	/// the work function that is run on the pthread.
	// 	internal let work:WorkFuncType

	// 	internal consuming func consumeArgument() -> A {
	// 		return argument
	// 	}
	// }

	/// function to run
	private let funct:Argument

	internal typealias Argument = () throws -> R
	internal typealias ReturnType = R

	internal init(_ argument:@escaping Argument) {
		self.funct = argument
	}

	internal mutating func run() throws -> R {
		return try funct()
	}
}

public func pthreadRun<R>(_ work:() throws -> R) async throws -> Result<R, Swift.Error> {
	try await withoutActuallyEscaping(work, do: { neWork in
		return try await PThreadFuncRunner<R>.run(neWork)
	})
}

extension PThreadWork {
	public static func run(_ arg:consuming Argument) async throws -> Result<ReturnType, Swift.Error> {
		let launchedPThread = try await launch(Self.self, argument:arg)
		defer {
			launchedPThread.join()
		}
		return await withTaskCancellationHandler(operation: {
			switch await launchedPThread.result() {
				case .success(let ptr):
					return .success(Unmanaged<Contained<ReturnType>>.fromOpaque(ptr).takeRetainedValue().accessContainedValue({
						return $0.pointee
					}))
				case .failure(let error):
					return .failure(error)
			}
		}, onCancel: {
			try! launchedPThread.cancel()
		})
	}
}

extension PThreadWork {
	// this is a bridge function that allows the c code to call the allocator function for the specific type in question. this is a critical step in the pthread lifecycle because this is where the initial argument is consumed.
	fileprivate init(_ ptr:UnsafeMutableRawPointer) {
		self = Unmanaged<Contained<Argument>>.fromOpaque(ptr).takeRetainedValue().accessContainedValue {
			return Self($0)
		}
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
		try! future.setSuccess(op) // this is allowed to fail because the future may have been canceled at the instant before this is called.
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
	private let returnFuture:Future<UnsafeMutableRawPointer> = Future<UnsafeMutableRawPointer>()

	// call this from within the pthread. this will initialize the workspace for the work that is about to begin on the pthread.
	fileprivate init(
		_ setup:Setup
	) {

		self.workspaceInstance = setup.thread_worktype.init(setup.containedArg)
		self.workspaceType = setup.thread_worktype
		self.configureFuture = setup.configureFuture
		
		// setup.deinitialize(count:1).deallocate()
	}

	fileprivate func setCancellation() {
		// set the return future to a failure error that is aproprate for cancellation.
		try? returnFuture.setFailure(CancellationError()) // this try may fail because its theoretically possible that the work returns an instant moment before this is called.

		try? configureFuture.setFailure(CancellationError()) // this may not fail because its presumed that if configureFuture is not already nil, then it is a valid future that must be set.
	}

	private func setSuccessfulConfiguration() {
		// set the configure future to success.
		try? configureFuture.setSuccess(returnFuture) // this may not fail because its presumed that if configureFuture is not already nil, then it is a valid future that must be set.
	}

	fileprivate mutating func work() {
		// set the configuration future to success.
		setSuccessfulConfiguration()

		// run the work and have it pass the result into the return future. in a successful case, this will pass a retained instance of Contained<ReturnType> into the return future.
		workspaceInstance.run(future:returnFuture)
	}
}

// assistive structure to define how a pthread shall be launched and ran.
fileprivate final class Setup {
	// a pointer to the contained argument
	fileprivate let containedArg:UnsafeMutableRawPointer

	// a pthread takes time to launch and configure itself before we can allow it to be canceled. this future will be set to success when the pthread is ready to be canceled.
	fileprivate var configureFuture:Future<Future<UnsafeMutableRawPointer>>

	// the type of pthread work to execute. this informs the pthread launch what kind of memory and work needs to be done.
	fileprivate let thread_worktype:any PThreadWork.Type

	fileprivate init<P>(_ workType:P.Type, containedArgument:UnsafeMutableRawPointer, configureFuture:Future<Future<UnsafeMutableRawPointer>>) where P:PThreadWork {
		self.containedArg = containedArgument
		self.thread_worktype = P.self
		self.configureFuture = configureFuture
	}

	deinit {
		// _ = configureFuture.takeRetainedValue()
		print("SETPU DEINIT")
	}
}

// this function makes three allocations. if the pthread is successfully launched, none of the memory needs to be deallocated. if the pthread fails to launch, the memory will be deallocated before the function throws.
fileprivate func launch<W, A>(_ workType:W.Type, argument:consuming A) async throws -> LaunchedPThread where W:PThreadWork, W.Argument == A {
	// allocate the memory where the pthread will be configured.
	let configureFuture = Future<Future<UnsafeMutableRawPointer>>()

	let setupContainer = Unmanaged<Setup>.passRetained(Setup(workType, containedArgument:Unmanaged.passRetained(Contained(argument)).toOpaque(), configureFuture:configureFuture))

	// launch the pthread, verify the results are successful.
	var launchResult:Int32 = -1
	let pthr = _cswiftslash_pthread_config_run(_cswiftslash_pthread_config_init(
		setupContainer.toOpaque(),
		_run_alloc,
		_run_main,
		_run_cancel,
		_run_dealloc
	), &launchResult)
	guard launchResult == 0 else {
		// balance the retained value that was passed into the pthread setup.
		_ = Unmanaged<Contained<A>>.fromOpaque(setupContainer.takeUnretainedValue().containedArg).takeRetainedValue()
		_ = setupContainer.takeRetainedValue()
		throw LaunchFailure()
	}

	// wait for the pthread to configure itself. at this point we can return the RunningPThread object through the future but we cant do so until the pthread is ready to be canceled. this is what we wait for.
	let returnFuture = try await configureFuture.get()
	return LaunchedPThread(pthr, future:returnFuture, type:workType)
}

// allocator function. responsible for initializing the workspace and transferring the crucial memory from the Setup.
fileprivate let _run_alloc:@convention(c) (_cswiftslash_ptr_t) -> _cswiftslash_ptr_t = { csPtr in
	print("alloc")
	return Unmanaged<Contained<Workspace>>.passRetained(
		Contained(
			Workspace(
				Unmanaged<Setup>.fromOpaque(csPtr).takeRetainedValue()
			)
		)
	).toOpaque()
}
// deallocator function. responsible for being as intentional as possible in capturing the current workspace and releasing the reference of it before it returns.
fileprivate let _run_dealloc:@convention(c) (_cswiftslash_ptr_t) -> Void = { wsPtr in
	print("dealloc")
	var ws:Contained? = Unmanaged<Contained<Workspace>>.fromOpaque(wsPtr).takeRetainedValue()
	ws = nil
}
// cancel function. responsible for setting the cancellation flag on the contained workspace.
fileprivate let _run_cancel:@convention(c) (_cswiftslash_ptr_t) -> Void = { wsPtr in
	print("cancel")
	Unmanaged<Contained<Workspace>>.fromOpaque(wsPtr).takeUnretainedValue().accessContainedValue { ws in
		ws.pointee.setCancellation()
	}
}
// main function. responsible for running the work function and setting the result into the return future.
fileprivate let _run_main:@convention(c) (_cswiftslash_ptr_t) -> Void = { wsPtr in
	print("main")
	// capture the contained workspace (nonretained because of pthread cancellation) so that we can interact with it safely for the work.
	Unmanaged<Contained<Workspace>>.fromOpaque(wsPtr).takeUnretainedValue().accessContainedValue { ws in
		ws.pointee.work()
	}
}