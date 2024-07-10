#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

import __cswiftslash
import Logging

// swiftslash is using pthread for the runtime loop that captures events from the kernel. this is so that the thread can be canceled while also using an indefinite wait time in the system polling call.
internal struct PThread<A, W, R> {
	private final class ContainedResult {
		private let result:R
		internal init(result:R) {
			self.result = result
		}
		internal borrowing func getResult() -> R {
			return result
		}
		deinit {
			// deallocate the result memory
			print("deallocating result")
		}
	}
	private final class ContainedWorkspace {
		private var stored:W
		internal init(_ stored:W) {
			self.stored = stored
		}
		internal borrowing func accessWorkspace(_ ws:(UnsafeMutablePointer<W>) throws -> R) rethrows -> R {
			return try withUnsafeMutablePointer(to:&stored) { sPtr in
				return try ws(sPtr)
			}
		}
		deinit {
			// deallocate the workspace memory
			print("deallocating workspace")
		}

	}
	internal static func run(arg:consuming A, work wf:@escaping (UnsafeMutablePointer<A>) throws -> R) async throws -> Result<R, Swift.Error> {
		// try await withoutActuallyEscaping(_allocF) { af in
			// try await withoutActuallyEscaping(_workF) { wf in
				
				// main task group for the pthread lifecycle.
				try await withThrowingTaskGroup(of:Void.self, returning:Result<R, Swift.Error>.self) { tg in
					// define futures for the crucial parts of the pthread lifecycle
					// launch future will be used to determine if the pthread was successfully launched
					let launchFuture = Future<_Running>()
					// this is the return future. in a successful case, it represents a Unmanaged<ContainedResult> with an unbalanced retain.
					let returnFuture = Future<RetPtr>(successfulResultDeallocator: {
						// work is returned as a an unmanaged object with an unbalanced retain count. we need to balance it here.
						_ = Unmanaged<ContainedResult>.fromOpaque($0).takeRetainedValue()
					})

					// launch the pthread
					tg.addTask { [arg] in
						var consumedArg = arg
						await withCheckedContinuation { cont in
							withUnsafeMutablePointer(to:&consumedArg) { argPtr in
								_run(argument:argPtr, launchFuture:launchFuture, returnFuture:returnFuture) { argPtr in
									// let result = try Unmanaged<ContainedWorkspace>.fromOpaque(wsPtr).takeUnretainedValue().accessWorkspace { wp in
										// return 
									// }
									// this returned value will fufill the return future with success
									return Unmanaged.passRetained(ContainedResult(result:try wf(argPtr.assumingMemoryBound(to:A.self)))).toOpaque()
								}
								cont.resume()
							}
						}
					}

					// wait for the pthread to begin running.
					switch await launchFuture.awaitResult() {
						case .success(let running):
						// verify that the task isn't already canceled.
						guard Task.isCancelled == false else {
							try! running.cancel()
							throw CancellationError()
						}
						// successful launch. wait for the work to return or throw.
						return await withTaskCancellationHandler(operation: {
							// wait for the work to return or throw
							switch await running.awaitResult() {
								case .success(let result):
									return .success(Unmanaged<ContainedResult>.fromOpaque(result).takeUnretainedValue().getResult())
								case .failure(let error):
									// work threw an error. we must pass this on
									return .failure(error)
							}
						}, onCancel: {
							try! running.cancel()
						})

						case .failure(let error):
						// failed to launch, we must throw
						throw error

					}
				}
			}
}

/// thrown when a pthread cannot be created.
internal struct LaunchError:Swift.Error {}

/// thrown when a pthread is unable to be canceled.
internal struct CancellationError:Swift.Error {}

fileprivate typealias RetPtr = UnsafeMutableRawPointer
fileprivate typealias WorkFunc = (UnsafeMutableRawPointer) throws -> RetPtr

// the contained setup struct that is passed into the pthread and used to set up / configure things.
fileprivate struct ContainedSetup {
	// the argument passed into the run function
	let arg:UnsafeMutableRawPointer

	// the work function to be run
	let work:WorkFunc

	// the configure future. this will fufill when the pthread is running its designated work and configured to properly cancel if needed.
	let configureFuture = Future<Future<RetPtr>>()

	// the future that will be set to success or failure depending on the success of the work function.
	let returnFuture:Future<RetPtr>

	/// the return value of the work if it didn't throw
	var workResult:RetPtr? = nil

	// the pointer to the workspace memory. the workspace memory is safely and reliably allocated and deallocated by the alloc and dealloc functions regardless if the pthread cancels or exits.
	var workspace:_cswiftslash_ptr_t? = nil

	internal init(_ arg:UnsafeMutableRawPointer, work:@escaping WorkFunc, returnFuture:Future<RetPtr>) {
		self.arg = arg
		self.work = work
		self.returnFuture = returnFuture
	}
}

fileprivate let _run_cancel:@convention(c) (_cswiftslash_ptr_t) -> Void = { csPtr in
	csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.returnFuture)!.pointee.setFailure(CancellationError())
}
fileprivate let _run_main:@convention(c) (_cswiftslash_ptr_t) -> Void = { csPtr in
	// thread is now configured and running. mark the configuring future as succeeded.
	csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.configureFuture)!.pointee.setSuccess((csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.returnFuture)!.pointee))

	do {
		// do the main work. pass the users argument and the workspace memory to the function.
		csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.workResult)!.pointee = try csPtr.assumingMemoryBound(to:ContainedSetup.self).pointee.work(csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.arg)!.pointee)
		
		// set the exit future to success since the work didn't throw
		csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.returnFuture)!.pointee.setSuccess(csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.workResult)!.pointee!)							
	} catch let error {
		// thread has thrown an error. set the exit future to failure.
		csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.returnFuture)!.pointee.setFailure(error)
	}
}

fileprivate struct _Running {
	/// the pthread primitive type that is used to represent the pthread.
	private let pt:_cswiftslash_pthread_t_type
	/// the future that will be set after the pthread has joined
	private let rf:Future<RetPtr>
	
	fileprivate init(_ pthread:consuming _cswiftslash_pthread_t_type, returnFuture:Future<RetPtr>) {
		pt = pthread
		rf = returnFuture
	}
	
	fileprivate func cancel() throws {
		guard pthread_cancel(pt) == 0 else {
			throw CancellationError()
		}
		// send signal
		guard pthread_kill(pt, SIGUSR1) == 0 else {
			throw CancellationError()
		}
	}
	
	fileprivate func awaitResult() async -> Result<RetPtr, Swift.Error> {
		await withCheckedContinuation { cont in
			cont.resume(returning:rf.blockForResult())
		}
	}
}

/// the primary function to call when you want to run a pthread and safely handle the memory around it.
/// - parameter usrArgPtr: the argument passed into the run function
/// - parameter alloc: the function to allocate the workspace memory
/// - parameter dealloc: the function to deallocate the workspace memory
/// - parameter launchFuture: the future that will be set to success or failure depending on the success of the pthread launch
fileprivate func _run(argument usrArgPtr:UnsafeMutableRawPointer, launchFuture:borrowing Future<_Running>, returnFuture:Future<RetPtr>, _ work:@escaping WorkFunc) {
	var containedSetup = ContainedSetup(usrArgPtr, work:work, returnFuture:returnFuture)
	withUnsafeMutablePointer(to:&containedSetup) { cSetupPtr in
		// launch the pthread
		var pthreadLaunchResult:Int32 = 0
		var pthreadPrimitiveInstance = _cswiftslash_pthread_fresh(nil, { csp in

			// pthread begin ----

			// main run function. this will configure the pthread to handle cancellation corrrctly. does not return.
			_cswiftslash_pthreads_main_f_run(csp, _run_main, _run_cancel)

		}, cSetupPtr, &pthreadLaunchResult);

		// verify the pthread was created successfully
		guard pthreadLaunchResult == 0 else {
			launchFuture.setFailure(LaunchError())
			return
		}

		// we now have a guarantee that configureFuture will be fufilled, so we will wait for that to happen now.
		switch cSetupPtr.pointer(to:\.configureFuture)!.pointee.blockForResult() {
			// the configure future has succeeded, we can now set the launch future to success.
			case .success:
			launchFuture.setSuccess(_Running(pthreadPrimitiveInstance, returnFuture:cSetupPtr.pointer(to:\.returnFuture)!.pointee))

			// this should never happen
			case .failure(let error):
			fatalError("unexpected error \(error) from \(#file):\(#line)")
		}

		cSetupPtr.pointer(to:\.returnFuture)!.pointee.blockForResult()

		// join the pthread, we have no regard for the return value.
		guard pthread_join(pthreadPrimitiveInstance, nil) == 0 else {
			fatalError("pthread_join error \(errno) from \(#file):\(#line)")
		}
	}
}