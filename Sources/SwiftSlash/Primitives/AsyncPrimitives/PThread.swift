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
		internal let result:R
		internal init(result:R) {
			self.result = result
		}
		internal borrowing func getResult() -> R {
			return result
		}
	}
	private final class ContainedWorkspace {
		private var stored:W
		internal init(_ stored:W) {
			self.stored = stored
		}
		internal borrowing func accessWorkspace<R>(_ ws:(UnsafeMutablePointer<W>) throws -> R) rethrows -> R {
			return try withUnsafeMutablePointer(to:&stored) { sPtr in
				return try ws(sPtr)
			}
		}
	}
	internal func run(_ arg:consuming A, alloc:() -> W, work:(UnsafeMutablePointer<A>, UnsafeMutablePointer<W>) throws -> R) async {
		let lf = Future<_Running>()

		try await withThrowingTaskGroup(of:Void.self, returning:Void.self) { tg in
			withUnsafeMutablePointer(to:&arg) { argPtr in
				_run(argument:argPtr, alloc: {
					return Unmanaged.passRetained(ContainedWorkspace(alloc())).toOpaque()
				}, dealloc: { wsPtr in
					_ = Unmanaged<ContainedWorkspace>.fromOpaque(wsPtr).takeRetainedValue()
				}, launchFuture:lf) { argPtr, wsPtr in
					let result = try Unmanaged<ContainedWorkspace>.fromOpaque(wsPtr).takeUnretainedValue().accessWorkspace { wp in
						return try work(argPtr.assumingMemoryBound(to:A.self), wp)
					}
					return Unmanaged.passRetained(ContainedResult(result:result)).toOpaque()
				}
			}
		}
	}
}

/// thrown when a pthread cannot be created.
internal struct LaunchError:Swift.Error {}

/// thrown when a pthread is unable to be canceled.
internal struct CancellationError:Swift.Error {}

/// the function that is run by the pthread.


fileprivate typealias RetPtr = UnsafeMutableRawPointer?
fileprivate typealias WorkFunc = (UnsafeMutableRawPointer, UnsafeMutableRawPointer) throws -> RetPtr?
fileprivate typealias DeallocFunc = (UnsafeMutableRawPointer) -> Void
fileprivate typealias AllocFunc = () -> UnsafeMutableRawPointer


fileprivate struct _Running {
	/// the pthread primitive type that is used to represent the pthread.
	private let pt:_cswiftslash_pthread_t_type
	/// the future that will be set after the pthread has joined
	private let rf:Future<RetPtr?>
	internal init(_ pthread:consuming _cswiftslash_pthread_t_type, returnFuture:Future<RetPtr?>) {
		pt = pthread
		rf = returnFuture
	}
	internal func cancel() throws {
		guard pthread_cancel(pt) == 0 else {
			throw CancellationError()
		}
	}
	internal func awaitResult() async -> Result<RetPtr?, Swift.Error> {
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
fileprivate func _run(argument usrArgPtr:UnsafeMutableRawPointer, alloc:AllocFunc, dealloc:DeallocFunc, launchFuture:borrowing Future<_Running>, _ _wf:WorkFunc) {
	
	// the contained setup struct that is passed into the pthread and used to set up / configure things.
	struct ContainedSetup {
		// the argument passed into the run function
		let arg:UnsafeMutableRawPointer

		// the work function to be run
		let work:WorkFunc
		// the alloc function to be run before the main work
		let alloc:AllocFunc
		// the dealloc function to be run after the main work or during cancellation
		let dealloc:DeallocFunc

		// the configure future. this will fufill when the pthread is running its designated work and configured to properly cancel if needed.
		let configureFuture = Future<Future<RetPtr?>>()

		// the future that will be set to success or failure depending on the success of the work function.
		let returnFuture = Future<RetPtr?>()

		/// the return value of the work if it didn't throw
		var workResult:RetPtr? = nil

		// the pointer to the workspace memory. the workspace memory is safely and reliably allocated and deallocated by the alloc and dealloc functions regardless if the pthread cancels or exits.
		var workspace:UnsafeMutableRawPointer? = nil

		internal init(_ arg:UnsafeMutableRawPointer, work:@escaping WorkFunc, alloc:@escaping AllocFunc, dealloc:@escaping DeallocFunc) {
			self.arg = arg
			self.work = work
			self.alloc = alloc
			self.dealloc = dealloc
		}
	}

	// none of these will actually escape
	withoutActuallyEscaping(_wf) { workEscaping in
		withoutActuallyEscaping(dealloc) { deallocEscaping in
			withoutActuallyEscaping(alloc) { allocEscaping in

				// initialize the contained setup, this is the primary exchange interface between the pthread memory and the calling context.
				var containedSetup = ContainedSetup(usrArgPtr, work:workEscaping, alloc:allocEscaping, dealloc:deallocEscaping)
				withUnsafeMutablePointer(to:&containedSetup) { cSetupPtr in
					
					// launch the pthread
					var pthreadLaunchResult:Int32 = 0
					var pthreadPrimitiveInstance = _cswiftslash_pthread_fresh(nil, { csp in

						// pthread begin ----
						
						// allocate the workspace
						csp.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.workspace)!.pointee = csp.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.alloc)!.pointee()

						// main run function. this will configure the pthread to handle cancellation corrrctly. does not return.
						_cswiftslash_pthreads_main_f_run(csp, { csPtr in

							// thread is now configured and running. mark the configuring future as succeeded.
							csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.configureFuture)!.pointee.setSuccess((csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.returnFuture)!.pointee))

							do {
								// do the main work. pass the users argument and the workspace memory to the function.
								csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.workResult)!.pointee = try csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.work)!.pointee(csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.arg)!.pointee, csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.workspace)!.pointee!)
								
								// set the exit future to success since the work didn't throw
								csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.returnFuture)!.pointee.setSuccess(csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.workResult)!.pointee!)

								// call the deallocator for the workspace memory
								csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.dealloc)!.pointee(csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.workspace)!.pointee!)
							
							} catch let error {
							
								// thread has thrown an error. set the exit future to failure.
								csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.returnFuture)!.pointee.setFailure(error)

								// call the deallocator for the workspace memory
								csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.dealloc)!.pointee(csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.workspace)!.pointee!)
							}
						}, { csPtr in
							// thread has been canceled. set the exit future to failure.
							csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.returnFuture)!.pointee.setFailure(CancellationError())

							// call the deallocator for the workspace memory
							csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.dealloc)!.pointee(csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.workspace)!.pointee!)
						})

					}, cSetupPtr, &pthreadLaunchResult);

					// verify the pthread was created successfully
					guard pthreadLaunchResult == 0 else {
						launchFuture.setFailure(LaunchError())
						return
					}

					// launch successful, we now have a guarantee that configureFuture will be fufilled, so we will wait for that to happen now.
					switch cSetupPtr.pointer(to:\.configureFuture)!.pointee.blockForResult() {
						// the configure future has succeeded, we can now set the launch future to success.
						case .success:
						launchFuture.setSuccess(_Running(pthreadPrimitiveInstance, returnFuture:cSetupPtr.pointer(to:\.returnFuture)!.pointee))

						// this should never happen
						case .failure(let error):
						fatalError("unexpected error \(error) from \(#file):\(#line)")
					}

					guard pthread_join(pthreadPrimitiveInstance, nil) == 0 else {
						fatalError("pthread_join error \(errno) from \(#file):\(#line)")
					}
				}
			}
		}
	}
}