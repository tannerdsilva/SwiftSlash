#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

import __cswiftslash
import SwiftSlashFuture

// swiftslash is using pthread for the runtime loop that captures events from the kernel. this is so that the thread can be canceled while also using an indefinite wait time in the system polling call.

/// thrown when a pthread cannot be created.
internal struct LaunchError:Swift.Error {}

/// thrown when a pthread is unable to be canceled.
internal struct CancellationError:Swift.Error {}

fileprivate func launchAsync<A, W>(arg:consuming A, _ ws:W.Type) async throws -> RunningPThread where W:PThreadWorkspace, W.Argument == A {
	return try await withThrowingDiscardingTaskGroup(body: { group in
		let future = Future<RunningPThread>()
		let containedArg = Unmanaged.passRetained(Contained(arg)).toOpaque()
		let setup = PThreadSetup(ws, containedArgument:containedArg)
		group.addTask {
			_launch(setup, runningFuture:future)
		}
		do {
			return try await future.waitForResult()
		} catch let error {
			_ = Unmanaged<Contained<A>>.fromOpaque(containedArg).takeRetainedValue()
			throw error
		}
	})
}

extension PThreadWorkspace {
	fileprivate init(_ ptr:UnsafeMutableRawPointer) {
		self.init(Unmanaged<Contained<Argument>>.fromOpaque(ptr).takeRetainedValue().consumeValue())
	}
	fileprivate mutating func run(future:borrowing Future<UnsafeMutableRawPointer>) {
		do {
			future.setSuccess(Unmanaged.passRetained(Contained(try run())).toOpaque())
		} catch let error {
			future.setFailure(error)
		}
	}

	fileprivate static func makeContainedReturnFuture() -> Future<UnsafeMutableRawPointer> {
		return Future<UnsafeMutableRawPointer>(successfulResultDeallocator: { ptr in
			_ = Unmanaged<Contained<ReturnType>>.fromOpaque(ptr).takeRetainedValue()
		})
	}
}

fileprivate final class Contained<A> {
	private let val:A
	fileprivate init(_ arg:A) {
		self.val = arg
	}
	fileprivate consuming func consumeValue() -> A {
		return val
	}
}

/// represents the memory space that is initialized and used within a pthread to accomplish a task.
fileprivate final class ContainedWorkspace {
	private var workspaceInstance:any PThreadWorkspace
	private let workspaceType:any PThreadWorkspace.Type

	private var configureFuture:Future<Future<UnsafeMutableRawPointer>>?
	private let returnFuture:Future<UnsafeMutableRawPointer>

	// call this from within the pthread. this will initialize the workspace for the work that is about to begin on the pthread.
	fileprivate init(
		_ setup:UnsafePointer<PThreadSetup>
	) {
		self.workspaceInstance = setup.pointer(to:\.thread_worktype)!.pointee.init(setup.pointer(to:\.containedArg)!.pointee)
		self.workspaceType = setup.pointer(to:\.thread_worktype)!.pointee
		self.configureFuture = setup.pointee.configureFuture
		self.returnFuture = setup.pointer(to:\.thread_worktype)!.pointee.makeContainedReturnFuture()
	}

	fileprivate borrowing func setCancellation() {
		// set the return future to a failure error that is aproprate for cancellation.
		returnFuture.setFailure(CancellationError())

		configureFuture?.setFailure(CancellationError())
		configureFuture = nil
	}

	private borrowing func setSuccessfulConfiguration() {
		// set the configure future to success.
		configureFuture?.setSuccess(returnFuture)
		configureFuture = nil
	}

	fileprivate borrowing func work() {
		// set the configuration future to success.
		setSuccessfulConfiguration()

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

	fileprivate init<P>(_ workType:P.Type, containedArgument:UnsafeMutableRawPointer) where P:PThreadWorkspace {
		self.containedArg = containedArgument
		self.thread_worktype = P.self
	}
}

fileprivate func _launch(_ config:borrowing PThreadSetup, runningFuture:consuming Future<RunningPThread>) {

	// consume the config immediately, expose it as an unsafe mutable pointer.
	withUnsafePointer(to:config) { ptSetup in

		// pass the resulting pointer into the pthread config as the primary argument for the allocator.
		var configuredStruct = _cswiftslash_pthread_config_init(
			ptSetup,
			_run_alloc,
			_run_main,
			_run_cancel,
			_run_dealloc
		);

		withUnsafeMutablePointer(to:&configuredStruct) { configPtr in
		
			// launch the pthread, verify the results are successful.
			var launchResult:Int32 = -1
			let pthr = _cswiftslash_pthread_config_run(configPtr, &launchResult)
			guard launchResult == 0 else {
				// if the pthread launch failed, set the running future to failure.
				runningFuture.setFailure(LaunchError())
				return
			}

			// wait for the pthread to configure itself. at this point we can return the RunningPThread object through the future but we cant do so until the pthread is ready to be canceled. this is what we wait for.
			switch ptSetup.pointer(to:\PThreadSetup.configureFuture)!.pointee.blockForResult() {
				case .success(let future):
					// set the running future to the RunningPThread object.
					runningFuture.setSuccess(RunningPThread(pthr, future:future))
				case .failure(let error):
					fatalError("pthread configuration failed: \(error) - this should never happen - \(#file) \(#line)")
			}
		}	
	}
}

// allocator function. responsible for initializing the workspace and transferring the crucial memory from the pthreadsetup.
fileprivate let _run_alloc:@convention(c) (_cswiftslash_cptr_t) -> _cswiftslash_ptr_t = { csPtr in
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