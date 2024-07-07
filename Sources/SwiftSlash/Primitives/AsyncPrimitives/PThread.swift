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
	/// the function that is run by the pthread.
	internal typealias WorkFunc = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void

	/// workspace allocator for the pthread.
	internal typealias WorkspaceAllocator = @convention(c) (UnsafeRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>) -> Void

	/// workspace deallocator for the pthread.
	internal typealias WorkspaceDeallocator = @convention(c) (UnsafeMutableRawPointer?) -> Void

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

	internal init(logger:consuming Logger, allocate:@escaping WorkspaceAllocator, work:@escaping WorkFunc, dealloc:@escaping WorkspaceDeallocator) async throws {
		self.configuration = PThread.ContainedConfiguration(logger, allocate:allocate, work:work, dealloc:dealloc)
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

		// this represents the result of the pthread_create call
		var threadLaunchResult:Int32 = 0
		// launch the pthread with the main function
		let newPT = _cswiftslash_pthread_fresh(nil, { PThread.pthreadMainWrapper($0) }, configPtr.toOpaque(), &threadLaunchResult)
		// if the result is not 0, the pthread was not created successfully
		guard threadLaunchResult == 0 else {
			// we have to reclaim the configuration because the pthread was not created
			_ = configPtr.takeRetainedValue()
			// with all resources now cleared up, we can now throw the launch error
			throw LaunchError()
		}
		#if os(Linux)
		// launch successful, assign the new pthread to this new instance
		self.pt_primitive = newPT
		#elseif os(macOS)
		guard newPT != nil else {
			fatalError("pthread_create error \(errno) from \(#file):\(#line)")
		}
		// launch successful, assign the new pthread to this new instance
		self.pt_primitive = newPT!
		#endif

		// wait for the pthread to engage with a CPU and begin working before returning from this function
		switch try await configuration.launchFuture.waitForResult() {
			case .success:
				return
			case .failure(let error):
				throw error
		}
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

		guard pthread_cancel(pt_primitive!) == 0 else {
			fatalError("pthread_cancel error \(errno) from \(#file):\(#line)")
		}

		guard pthread_kill(pt_primitive!, SIGUSR1) == 0 else {
			fatalError("pthread_kill error \(errno) from \(#file):\(#line)")
		}
	}

	/// waits for the returning result of the pthread 
	internal borrowing func waitForResult() async throws -> Result<Void, Error> {
		return try await configuration.getResult()
	}

	deinit {
		// the pthread instance was fully dereferenced. we must fully clean up the pthread and its supporting resources based on the operating mode the instance is in.

		// the mode struct must be copied from the instance so we can use it as a mutable pointer
		var finalMode = mode

		// apply an atomic load onto the copied struct so that we can determine the state it was operating in.
		let loadedMode = _cswiftslash_auint8_load(&finalMode)

		// if the pthread is running and it is not canceled, cancel it.
		if (loadedMode & PThreadOperationMode.running.rawValue != 0) && (loadedMode & PThreadOperationMode.canceled.rawValue == 0) {
			guard pthread_cancel(pt_primitive!) == 0 else {
				fatalError("pthread_cancel error \(errno) from \(#file):\(#line)")
			}
		}

		// if the thread is not dead, join it.
		guard loadedMode != PThreadOperationMode.dead.rawValue else {
			return
		}

		var retPtr:UnsafeMutableRawPointer? = nil
		guard pthread_join(pt_primitive!, &retPtr) == 0 else {
			fatalError("pthread_join error \(errno) from \(#file):\(#line)")
		}
		_ = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(retPtr!).takeRetainedValue()
	}
}

extension PThread {

	/// main function that handles the unwrapping of the logger before calling the main function.
	private static func pthreadMainWrapper(_ ptr:UnsafeMutableRawPointer) -> Never {
		// set deferred cancellation state
		pthread_setcanceltype(Int32(PTHREAD_CANCEL_DEFERRED), nil);
		pthread_setcancelstate(Int32(PTHREAD_CANCEL_DISABLE), nil);

		_cswiftslash_pthreads_main_f_run(ptr, { configPtr, workspacePtr in 
			// use an unretained value because the root function is retaining the configuration
			let pthreadConfig = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(configPtr).takeUnretainedValue()
			pthreadConfig.launchFuture.setSuccess()

			// run the configured task
			pthreadConfig.getRunFunction()(configPtr, workspacePtr)

		}, { configPtr, allocateWorkspace in
			// obtain the allocator function from the configuration and call it with the workspace pointer
			Unmanaged<PThread.ContainedConfiguration>.fromOpaque(configPtr).takeUnretainedValue().getAllocFunction()(configPtr, allocateWorkspace)
		}, { configPtr, deallocateWorkspace in 
			// obtain the deallocator function from the configuration and call it with the workspace pointer
			let config = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(configPtr).takeUnretainedValue()
			config.getDeallocFunction()(deallocateWorkspace)
		}, { configPtr in
			// use an unretained value because the root function is retaining the configuration
			let pthreadConfig = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(configPtr).takeUnretainedValue()
			pthreadConfig.setResult(.failure(CancellationError()))
		})

		// pthread_exit(UnsafeMutableRawPointer(mutating:nil))
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


	private final class Workspace {
		deinit {
			print("WORKSPACE DEINIT")
		}
	}

	/// this class is used to pass a logger to the pthread in a relatively swift-friedly way.
	private final class ContainedConfiguration {
		private let logger:Logger
		private let allocFunc:WorkspaceAllocator
		private let runFunc:WorkFunc
		private let deallocFunc:WorkspaceDeallocator
		private let resultFuture = Future()
		internal let launchFuture = Future()
		private let allowedSignals:sigset_t
		private enum Mode:UInt8 {
			case hasResult = 1
			case noResult = 0
		}
		internal init(_ logger:Logger, allocate:@escaping WorkspaceAllocator, work runFunc:@escaping WorkFunc, dealloc:@escaping WorkspaceDeallocator) {
			self.logger = logger
			self.allocFunc = allocate
			self.runFunc = runFunc
			self.deallocFunc = dealloc
			// self.sem = _cswiftslash_sem_fresh(0)
			var allowedSignals = sigset_t()
			sigemptyset(&allowedSignals)
			sigaddset(&allowedSignals, SIGUSR1)
			self.allowedSignals = allowedSignals
		}

		internal func getLogger() -> Logger {
			return logger
		}
		internal func getRunFunction() -> WorkFunc {
			return runFunc
		}
		internal func getAllocFunction() -> WorkspaceAllocator {
			return allocFunc
		}
		internal func getDeallocFunction() -> WorkspaceDeallocator {
			return deallocFunc
		}
		internal func setResult(_ result:Result<Void, Error>) {
			switch result {
				case .success:
					resultFuture.setSuccess()
				case .failure(let error):
					resultFuture.setFailure(error)
			}
		}
		internal func getResult() async throws -> Result<Void, Error> {
			return try await resultFuture.waitForResult()
		}
	}
}
