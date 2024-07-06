#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

import __cswiftslash
import Logging

internal struct PThreadOperationMode:OptionSet {
	internal let rawValue:UInt8

	/// this is the explicit value of the mode byte when the pthread is dead.
	internal static let dead: PThreadOperationMode = PThreadOperationMode(rawValue:0)

	/// this flag is enabled when the pthread is running.
	internal static let running = PThreadOperationMode(rawValue:1)

	/// this flag is enabled when the pthread has been sent a cancel signal.
	internal static let canceled = PThreadOperationMode(rawValue:1 << 1)
}

// swiftslash is using pthread for the runtime loop that captures events from the kernel. this is so that the thread can be canceled while also using an indefinite wait time in the system polling call.
internal struct PThread:~Copyable {
	/// thrown when a pthread cannot be created.
	internal struct LaunchError:Swift.Error {}
	
	/// thrown when an operation cannot be completed because the pthread is in an invalid state.
	internal struct InvalidModeError:Swift.Error {
		internal let mode:PThreadOperationMode
		internal init(mode:PThreadOperationMode) {
			self.mode = mode
		}
	}

	/// the pthread primitive.
	private var pt_primitive:_cswiftslash_pthread_t_type? = nil

	/// the mode that this pthread instance is currently operating in.
	private var mode:_cswiftslash_atomic_uint8_t

	/// the configuration for this pthread instance.
	private let configuration:ContainedConfiguration

	internal init(logger:consuming Logger, _ f:@escaping (borrowing Logger) throws -> Void) async throws {
		self.configuration = PThread.ContainedConfiguration(logger, run:f)
		var mode = _cswiftslash_atomic_uint8_t()
		_cswiftslash_auint8_store(&mode, PThreadOperationMode.dead.rawValue)
		self.mode = mode
	}

	/// start the pthread. the function is async because it waits for the thread to begin running its work before returning.
	/// - throws: InvalidModeError if the pthread is already running or has been canceled.
	internal mutating func start() async throws {
		// read the existing mode from memory
		var existingMode = _cswiftslash_auint8_load(&mode)

		// validate this isn't already running
		guard existingMode == PThreadOperationMode.dead.rawValue else {
			throw InvalidModeError(mode:PThreadOperationMode(rawValue:existingMode))
		}

		// apply the existing flags with the running flag
		guard _cswiftslash_auint8_compare_exchange_weak(&mode, &existingMode, existingMode | PThreadOperationMode.running.rawValue) else {
			throw InvalidModeError(mode:PThreadOperationMode(rawValue:existingMode))
		}

		// pass the configuration of this instance into an unmanaged pointer to be passed into the pthread after it is launched
		let configPtr = Unmanaged.passRetained(configuration)

		#if os(Linux)
		guard pthread_create(&pt_primitive, nil, { PThread.mainWrapper($0!) }, configPtr.toOpaque()) == 0 else {
			_ = configPtr.takeRetainedValue()
			throw LaunchError()
		}
		#elseif os(macOS)
		// this represents the result of the pthread_create call
		var threadLaunchResult:Int32 = 0
		// launch the pthread with the main function
		let newPT = _cswiftslash_pthread_fresh(nil, { PThread.pthreadMainWrapper($0)! }, configPtr.toOpaque(), &threadLaunchResult)
		// if the result is not 0, the pthread was not created successfully
		guard threadLaunchResult == 0 else {
			// we have to reclaim the configuration because the pthread was not created
			_ = configPtr.takeRetainedValue()
			// with all resources now cleared up, we can now throw the launch error
			throw LaunchError()
		}

		// launch successful, assign the new pthread to this new instance
		self.pt_primitive = newPT!
		#endif

		// wait for the pthread to engage with a CPU and begin working before returning from this function
		await configuration.waitForLaunch()
	}

	/// cancels a pthread if it is in a running state.
	/// - throws: InvalidModeError if the pthread is not in a running state or has already been canceled.	
	internal mutating func cancel() throws {
		// read the existing mode from memory
		var existingMode = _cswiftslash_auint8_load(&mode)

		// validate this isn't already canceled or dead
		guard (existingMode != 0) && (existingMode & PThreadOperationMode.canceled.rawValue == 0) else {
			throw InvalidModeError(mode:PThreadOperationMode(rawValue:existingMode))
		}

		// apply the existing value with the cancelled flag
		guard _cswiftslash_auint8_compare_exchange_weak(&mode, &existingMode, existingMode | PThreadOperationMode.canceled.rawValue) else {
			throw InvalidModeError(mode:PThreadOperationMode(rawValue:existingMode))
		}

		// success, cancel the pthread
		#if os(Linux)
		guard pthread_cancel(pt_primitive) == 0 else {
			fatalError("pthread_cancel error \(errno) from \(#file):\(#line)")
		}
		#elseif os(macOS)
		guard pthread_cancel(pt_primitive!) == 0 else {
			fatalError("pthread_cancel error \(errno) from \(#file):\(#line)")
		}
		#endif
	}

	/// waits for the returning result of the pthread 
	internal borrowing func waitForResult() async -> Result<Void, Error> {
		return await configuration.getResult()
	}

	deinit {
		// the pthread instance was fully dereferenced. we must fully clean up the pthread and its supporting resources based on the operating mode the instance is in.

		// the mode struct must be copied from the instance so we can use it as a mutable pointer
		var finalMode = mode

		// apply an atomic load onto the copied struct so that we can determine the state it was operating in.
		let loadedMode = _cswiftslash_auint8_load(&finalMode)

		// if the pthread is running and it is not canceled, cancel it.
		if (loadedMode & PThreadOperationMode.running.rawValue != 0) && (loadedMode & PThreadOperationMode.canceled.rawValue == 0) {
			#if os(Linux)
			guard pthread_cancel(pt_primitive) == 0 else {
				fatalError("pthread_cancel error \(errno) from \(#file):\(#line)")
			}
			#elseif os(macOS)
			guard pthread_cancel(pt_primitive!) == 0 else {
				fatalError("pthread_cancel error \(errno) from \(#file):\(#line)")
			}
			#endif
		}

		// if the thread is not dead, join it.
		guard loadedMode != PThreadOperationMode.dead.rawValue else {
			return
		}

		#if os(Linux)
		var retPtr:UnsafeMutableRawPointer? = nil
		guard pthread_join(pt_primitive, &retPtr) == 0 else {
			fatalError("pthread_join error \(errno) from \(#file):\(#line)")
		}
		_ = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(retPtr!).takeRetainedValue()
		#elseif os(macOS)
		var retPtr:UnsafeMutableRawPointer? = nil
		guard pthread_join(pt_primitive!, &retPtr) == 0 else {
			fatalError("pthread_join error \(errno) from \(#file):\(#line)")
		}
		_ = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(retPtr!).takeRetainedValue()
		#endif
	}
}

extension PThread {

	/// main function that handles the unwrapping of the logger before calling the main function.
	private static func pthreadMainWrapper(_ ptr:UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {

		// this is the retaining variable for this entire function
		var config:PThread.ContainedConfiguration? = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(ptr).takeRetainedValue()
		
		// create an unsafe mutable pointer 
		withUnsafeMutablePointer(to:&config) { cfg in
			_cswiftslash_pthreads_main_f_run(cfg, { configPtr, workspacePtr in 
				// pthread_testcancel()
				pthread_testcancel()
				// use an unretained value because the root function is retaining the configuration
				let pthreadConfig = configPtr!.assumingMemoryBound(to:PThread.ContainedConfiguration?.self).pointee
				pthreadConfig!.signalLaunched()
				do {
					// run the configured task
					try pthreadConfig!.getRunFunction()(pthreadConfig!.getLogger())
					// task complete. pass the success result to the future
					pthreadConfig?.withFuture { f in
						_ = _cswiftslash_future_t_broadcast_res_val(f, 0, nil)
					}
				} catch let error {
					// task failed. pass the error result to the future
					pthreadConfig?.withFuture { f in
						let result = Unmanaged.passRetained(PThread.ContainedError(err:error))
						guard _cswiftslash_future_t_broadcast_res_val(f, 0, result.toOpaque()) == true else {
							_ = result.takeRetainedValue()
							return
						}
						return
					}
				}
			}, { allocateSpace in
				print("ALLOC")
				allocateSpace.pointee = Unmanaged.passRetained(Workspace()).toOpaque()
			}, { deallocateSpace in 
				print("DEALLOC")
				_ = Unmanaged<Workspace>.fromOpaque(deallocateSpace!).takeRetainedValue()
			}, { configPtr in
				// use an unretained value because the root function is retaining the configuration
				let config = configPtr!.assumingMemoryBound(to:PThread.ContainedConfiguration?.self)
				config.pointee!.withFuture { f in
					_ = _cswiftslash_future_t_broadcast_cancel(f)
				}
				config.pointee = nil
			})
		}
		// var logger = config.getLogger()
		// let tid = pthread_self()
		// logger[metadataKey:"pthread_id"] = "\(tid)"
		// logger.debug("pthread launched")

		
		
		return ptr
	}

	private final class ContainedResult {
		internal let result:Result<Void, Swift.Error>
		internal init(result:Result<Void, Swift.Error>) {
			self.result = result
		}
	}
	private final class ContainedError {
		internal let err:Swift.Error
		internal init(err:Swift.Error) {
			self.err = err
		}
	}
	
	private final class Sem {
		private var sem:_cswiftslash_sem_t_type
		internal init() {
			self.sem = _cswiftslash_sem_fresh(0)
		}
		internal func signal() {
			_cswiftslash_sem_signal(&sem)
		}
		internal func wait() {
			_cswiftslash_sem_wait(&sem)
		}
		deinit {
			_cswiftslash_sem_destroy(&sem)
		}	
	}

	private final class Workspace {
		deinit {
			print("WORKSPACE DEINIT")
		}
	}

	/// this class is used to pass a logger to the pthread in a relatively swift-friedly way.
	private final class ContainedConfiguration {
		private let logger:Logger
		private let runFunc:(borrowing Logger) throws -> Void
		private var result:Result<Void, Error>? = nil
		private var future:_cswiftslash_future_t = _cswiftslash_future_t()
		private var sem:_cswiftslash_sem_t_type
		private enum Mode:UInt8 {
			case hasResult = 1
			case noResult = 0
		}
		internal init(_ logger:Logger, run runFunc:@escaping (borrowing Logger) throws -> Void) {
			self.logger = logger
			self.runFunc = runFunc
			self.sem = _cswiftslash_sem_fresh(0)
		}
		internal func signalLaunched() {
			_cswiftslash_sem_signal(&sem)
		}
		internal func waitForLaunch() async {
			await withCheckedContinuation({
				_cswiftslash_sem_wait(&sem)
				$0.resume()
			})
		}
		internal func getLogger() -> Logger {
			return logger
		}
		internal func getRunFunction() -> (borrowing Logger) throws -> Void {
			return runFunc
		}
		internal func withFuture<R>(_ f:(UnsafeMutablePointer<_cswiftslash_future_t>) -> R) -> R {
			f(&future)
		}
		internal func getResult() async -> Result<Void, Error> {
			return await withCheckedContinuation({ cont in
				var getResult:Result<Void, Swift.Error>? = nil
				withUnsafeMutablePointer(to:&getResult) { returnResultPtr in
					_cswiftslash_future_t_wait_sync(&future, { _ in 
						returnResultPtr.pointee = .success(())
					}, { errPtr in 
						let error = Unmanaged<PThread.ContainedError>.fromOpaque(errPtr!).takeUnretainedValue().err
						returnResultPtr.pointee = .failure(error)
					}, {
						returnResultPtr.pointee = .failure(CancellationError())
					})
				}
				cont.resume(returning:getResult!)
			})
		}
		deinit {
			_cswiftslash_future_t_destroy(&future, { _ in return }, { errPtr in
				_ = Unmanaged<PThread.ContainedError>.fromOpaque(errPtr!).takeRetainedValue()
			})
			_cswiftslash_sem_destroy(&sem)
		}
	}
}
