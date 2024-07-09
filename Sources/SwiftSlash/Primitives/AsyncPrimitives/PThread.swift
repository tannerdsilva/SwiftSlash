#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

import __cswiftslash
import Logging

// swiftslash is using pthread for the runtime loop that captures events from the kernel. this is so that the thread can be canceled while also using an indefinite wait time in the system polling call.
internal struct PThread<A, W> {
	private final class ContainedWorkspace {
		private let stored:W
		internal init(_ stored:W) {
			self.stored = stored
		}
		internal func getWorkspace() -> W {
			return stored
		}
	}
	internal func run(_ arg:consuming A, alloc:() -> W, work:(UnsafeMutablePointer<A>, W) throws -> Void) {
		let lf = Future<Running>()
		withUnsafeMutablePointer(to:&arg) { argPtr in
			_run(argument:argPtr, alloc: {
				return Unmanaged.passRetained(ContainedWorkspace(alloc())).toOpaque()
			}, dealloc: { wsPtr in
				_ = Unmanaged<ContainedWorkspace>.fromOpaque(wsPtr).takeRetainedValue()
			}, launchFuture:lf) { argPtr, wsPtr in
				try work(argPtr.assumingMemoryBound(to:A.self), Unmanaged<ContainedWorkspace>.fromOpaque(wsPtr).takeUnretainedValue().getWorkspace())
			}
		}
		
	}
}

/// thrown when a pthread cannot be created.
internal struct LaunchError:Swift.Error {}

/// thrown when a pthread is unable to be canceled.
internal struct CancellationError:Swift.Error {}

/// the function that is run by the pthread.
internal typealias WorkFunc = (UnsafeMutableRawPointer, UnsafeMutableRawPointer) throws -> Void

internal typealias DeallocFunc = (UnsafeMutableRawPointer) -> Void

internal typealias AllocFunc = () -> UnsafeMutableRawPointer


fileprivate struct Running {
	private let pt:_cswiftslash_pthread_t_type
	private let rf:Future<Void>
	internal init(_ pthread:consuming _cswiftslash_pthread_t_type, returnFuture:Future<Void>) {
		pt = pthread
		rf = returnFuture
	}
	internal consuming func cancel() throws {
		guard pthread_cancel(pt) == 0 else {
			throw CancellationError()
		}
	}
}


// internal static func run<A>(argument arg:consuming A)
fileprivate func _run(argument usrArgPtr:UnsafeMutableRawPointer, alloc:AllocFunc, dealloc:DeallocFunc, launchFuture:borrowing Future<Running>, _ _wf:WorkFunc) {
	
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

		// the launch future
		let configureFuture = Future<Future<Void>>()

		let returnFuture = Future<Void>()

		// the pointer to the user pointer
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
						
						// allocate the workspace
						csp.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.workspace)!.pointee = csp.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.alloc)!.pointee()

						// main run function
						_cswiftslash_pthreads_main_f_run(csp, { csPtr in

							// thread is now configured and running. mark the configuring future as succeeded.
							csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.configureFuture)!.pointee.setSuccess((csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.returnFuture)!.pointee))

							do {
								// do the main work. pass the users argument and the workspace memory to the function.
								try csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.work)!.pointee(csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.arg)!.pointee, csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.workspace)!.pointee!)
								
								// set the exit future to success since the work didn't throw
								csPtr.assumingMemoryBound(to:ContainedSetup.self).pointer(to:\.returnFuture)!.pointee.setSuccess(())

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
						case .success:
						launchFuture.setSuccess(Running(pthreadPrimitiveInstance, returnFuture:cSetupPtr.pointer(to:\.returnFuture)!.pointee))
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