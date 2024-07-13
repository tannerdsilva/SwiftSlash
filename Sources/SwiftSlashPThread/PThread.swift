#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

import __cswiftslash

// swiftslash is using pthread for the runtime loop that captures events from the kernel. this is so that the thread can be canceled while also using an indefinite wait time in the system polling call.

/// thrown when a pthread cannot be created.
internal struct LaunchError:Swift.Error {}

/// thrown when a pthread is unable to be canceled.
internal struct CancellationError:Swift.Error {}


internal protocol PThreadArgument {}

internal protocol PThreadWorkspace {
	associatedtype Argument:PThreadArgument
	init(_ ptr:UnsafeMutableRawPointer)
}

internal protocol PThreadWork {
	associatedtype Workspace:PThreadWorkspace
	static func allocate(_ ptr:UnsafeMutableRawPointer) -> Workspace
	static func work(_:UnsafeMutableRawPointer) throws -> UnsafeMutableRawPointer?
}

extension PThreadWork {
	internal static func allocate(_ ptr:UnsafeMutableRawPointer) -> Workspace {
		return Workspace(ptr)
	}
}

/// represents the memory space that is initialized and used within a pthread to accomplish a task.
fileprivate final class ContainedWorkspace {
	private var workspace:any PThreadWorkspace
	private let workspaceType:any PThreadWork.Type

	private let configureFuture:Future<Future<UnsafeMutableRawPointer?>>
	private let returnFuture:Future<UnsafeMutableRawPointer?> = Future<UnsafeMutableRawPointer?>()

	internal init(
		_ setup:UnsafePointer<PThreadSetup>
	) {
		self.workspace = setup.pointer(to:\.thread_worktype)!.pointee.allocate(setup.pointer(to:\.usr_alloc_arg)!.pointee)
		self.workspaceType = setup.pointer(to:\.thread_worktype)!.pointee
		self.configureFuture = setup.pointee.configureFuture
	}

	fileprivate borrowing func setCancellation() {
		// set the return future to a failure error that is aproprate for cancellation.
		returnFuture.setFailure(CancellationError())
		configureFuture.setFailure(CancellationError())
	}

	private borrowing func setSuccessfulConfiguration() {
		// set the configure future to success.
		configureFuture.setSuccess(returnFuture)
	}

	private borrowing func workResult() -> Result<UnsafeMutableRawPointer?, Swift.Error> {
		do {
			return try withUnsafeMutablePointer(to:&workspace) { wsPtr in
				return .success(try workspaceType.work(wsPtr))
			}
		} catch let e {
			return .failure(e)
		}
	}

	private borrowing func returnedResult(_ result:consuming Result<UnsafeMutableRawPointer?, Swift.Error>) {
		switch result {
			case .success(let res):
				returnFuture.setSuccess(res)
			case .failure(let error):
				returnFuture.setFailure(error)
		}
	}

	fileprivate borrowing func work() {
		// set the configuration future to success.
		setSuccessfulConfiguration()

		// run the work function and set the result into the return future.
		returnedResult(workResult())
	}
}

// the contained setup struct that is passed into the pthread and used to set up / configure things.
fileprivate struct PThreadSetup {
	// a pointer that will be passed into 
	fileprivate let usr_alloc_arg:UnsafeMutableRawPointer

	// a pthread takes time to launch and configure itself before we can allow it to be canceled. this future will be set to success when the pthread is ready to be canceled.
	fileprivate let configureFuture:Future<Future<UnsafeMutableRawPointer?>> = Future<Future<UnsafeMutableRawPointer?>>()

	// the running future that will fufill when the pthread is launched and working.
	fileprivate let runFuture:Future<RunningPThread> = Future<RunningPThread>()

	// the type of pthread work to execute. this informs the pthread launch what kind of memory and work needs to be done.
	fileprivate let thread_worktype:any PThreadWork.Type

	fileprivate init<P>(_ workType:P.Type, usr_alloc_arg:UnsafeMutableRawPointer, runFuture:Future<RunningPThread>) where P:PThreadWork {
		self.usr_alloc_arg = usr_alloc_arg
		self.thread_worktype = P.self
	}
}

fileprivate let _run_alloc:@convention(c) (_cswiftslash_ptr_t) -> _cswiftslash_ptr_t = { csPtr in
	return Unmanaged<ContainedWorkspace>.passRetained(
		ContainedWorkspace(
			csPtr.assumingMemoryBound(to:PThreadSetup.self)
		)
	).toOpaque()
}
fileprivate let _run_dealloc:@convention(c) (_cswiftslash_ptr_t) -> Void = { wsPtr in
	var ws:ContainedWorkspace? = Unmanaged<ContainedWorkspace>.fromOpaque(wsPtr).takeRetainedValue()
	ws = nil
}
fileprivate let _run_cancel:@convention(c) (_cswiftslash_ptr_t) -> Void = { wsPtr in
	Unmanaged<ContainedWorkspace>.fromOpaque(wsPtr).takeUnretainedValue().setCancellation()
}
fileprivate let _run_main:@convention(c) (_cswiftslash_ptr_t) -> Void = { wsPtr in
	// capture the contained workspace (nonretained because of pthread cancellation) so that we can interact with it safely for the work.
	withUnsafePointer(to:Unmanaged<ContainedWorkspace>.fromOpaque(wsPtr).takeUnretainedValue()) { containerPtr in 
		// run the work function, pass the result into the return future.
		containerPtr.pointee.work()
	}
}

/// primary function for running pthread work in an async swift runtime. THIS FUNCTION IS BLOCKING. calls pthread_create and pthread_join unconditionally to ensure full lifecycle safety.
/// - parameters:
/// 	- config: the configuration that defines what kind of executable work and memory space the newly created pthread will use.
/// - throws: LaunchError if the pthread cannot be created.
/// - WARNING: THIS FUNCTION WILL BLOCK and as such, breaks the swift async runtime model. be sure to call within a continuation.
fileprivate func _run(_ config:consuming PThreadSetup) throws {

	// consume the config immediately, expose it as an unsafe mutable pointer.
	try withUnsafeMutablePointer(to:&config) { ptSetup in

		// pass the resulting pointer into the pthread config as the primary argument for the allocator.
		var configuredStruct = _cswiftslash_pthread_config_init(
			ptSetup,
			_run_alloc,
			_run_main,
			_run_cancel,
			_run_dealloc
		);

		try withUnsafeMutablePointer(to:&configuredStruct) { configPtr in
		
			// launch the pthread, verify the results are successful.
			var launchResult:Int32 = -1
			let config = _cswiftslash_pthread_config_run(configPtr, &launchResult)
			guard launchResult == 0 else {
				// unsuccessful pthread launch - throw. there shouldn't be a need to clean up the configuration struct or any other memory.
				throw LaunchError()
			}

			defer {
				var returnPointer:UnsafeMutableRawPointer? = nil
				guard pthread_join(config, &returnPointer) == 0 else {
					fatalError("pthread_join failed")
				}
			}

			// wait for the pthread to configure itself. at this point we can return the RunningPThread object through the future but we cant do so until the pthread is ready to be canceled. this is what we wait for.
			switch config.pointee.configureFuture.blockForResult() {
				case .success(let returnFuture):
					let makeRunning = RunningPThread(config, returnFuture:returnFuture)
					ptSetup.pointer(to:\.runFuture)!.pointee.setSuccess(makeRunning)

				case .failure(let error):
					// pthread was canceled before it could be configured.
					throw error
			}
		}	
	}
}