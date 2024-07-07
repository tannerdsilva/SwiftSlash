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

	/// this flag is enabled when the pthread is joining.
	internal static let joining = PThreadOperationMode(rawValue:1 << 2)
}

fileprivate struct AUInt8:~Copyable {
	private var value:_cswiftslash_atomic_uint8_t = _cswiftslash_atomic_uint8_t()
	fileprivate mutating func load() -> UInt8 {
		return _cswiftslash_auint8_load(&value)
	}
	fileprivate mutating func store(_ newValue:UInt8) {
		_cswiftslash_auint8_store(&value, newValue)
	}
	fileprivate mutating func compareExchangeWeak(expected:inout UInt8, desired:UInt8) -> Bool {
		return _cswiftslash_auint8_compare_exchange_weak(&value, &expected, desired)
	}
}

extension _cswiftslash_pthread_t_type:@unchecked Sendable {}

// swiftslash is using pthread for the runtime loop that captures events from the kernel. this is so that the thread can be canceled while also using an indefinite wait time in the system polling call.
internal final class PThread {
	/// the function that is run by the pthread.
	internal typealias WorkFunc = @convention(c) (UnsafeRawPointer?, UnsafeMutableRawPointer?) -> Void

	/// workspace allocator for the pthread.
	internal typealias WorkspaceAllocator = @convention(c) () -> UnsafeMutableRawPointer?

	/// workspace deallocator for the pthread.
	internal typealias WorkspaceDeallocator = @convention(c) (UnsafeRawPointer?) -> Void

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
	private var _pt:_cswiftslash_pthread_t_type? = nil

	/// the mode that this pthread instance is currently operating in.
	private var mode = AUInt8()

	private var argument:UnsafeRawPointer?

	private var allocate:WorkspaceAllocator?
	private var dealloc:WorkspaceDeallocator?

	private var work:WorkFunc?

	internal init(argument:UnsafeRawPointer? = nil, alloc:@escaping WorkspaceAllocator, dealloc:@escaping WorkspaceDeallocator, _ work:@escaping WorkFunc) {
		self.allocate = alloc
		self.dealloc = dealloc
		self.work = work
		self.argument = argument
	}

	/// start the pthread. the function is async because it waits for the thread to begin running its work before returning.
	/// - throws: InvalidModeError if the pthread is already running or has been canceled.
	internal func start() throws -> Future {

		// read the existing mode from memory
		var existingMode = mode.load()

		// validate this isn't already running
		guard existingMode == PThreadOperationMode.dead.rawValue else {
			throw InvalidModeError(mode:PThreadOperationMode(rawValue:existingMode))
		}

		// apply the existing flags with the running flag
		guard mode.compareExchangeWeak(expected:&existingMode, desired:PThreadOperationMode.running.rawValue) else {
			throw InvalidModeError(mode:PThreadOperationMode(rawValue:existingMode))
		}

		// pass the configuration of this instance into an unmanaged pointer to be passed into the pthread after it is launched
		let configPtr = Unmanaged.passRetained(ContainedConfiguration(arg:argument, allocate:allocate!, work:work!, dealloc:dealloc!))

		// this represents the result of the pthread_create call
		var threadLaunchResult:Int32 = 0
		// launch the pthread with the main function
		let newPT = _cswiftslash_pthread_fresh(nil, { PThread.pthreadMainWrapper($0) }, configPtr.toOpaque(), &threadLaunchResult)
		// if the result is not 0, the pthread was not created successfully
		guard threadLaunchResult == 0 else {
			_ = configPtr.takeRetainedValue()
			// with all resources now cleared up, we can now throw the launch error
			throw LaunchError()
		}

		#if os(Linux)
		// launch successful, assign the new pthread to this new instance
		self._pt = newPT
		#elseif os(macOS)
		self._pt = newPT!
		#endif

		// wait for the pthread to engage with a CPU and begin working before returning from this function
		switch try configPtr.takeUnretainedValue().launchFuture.waitForResult() {
			case .success:
			return configPtr.takeUnretainedValue().getResultFuture()
			case .failure(let error):
				throw error
		}
	}

	/// cancels a pthread if it is in a running state.
	/// - throws: InvalidModeError if the pthread is not in a running state or has already been canceled.	
	internal func cancel() throws {
		// read the existing mode from memory
		var existingMode = mode.load()

		// validate this isn't already canceled or dead
		guard (existingMode != 0) && (existingMode & PThreadOperationMode.canceled.rawValue == 0) else {
			throw InvalidModeError(mode:PThreadOperationMode(rawValue:existingMode))
		}

		// apply the existing value with the cancelled flag
		guard mode.compareExchangeWeak(expected:&existingMode, desired:existingMode | PThreadOperationMode.canceled.rawValue) else {
			throw InvalidModeError(mode:PThreadOperationMode(rawValue:existingMode))
		}

		guard pthread_cancel(_pt!) == 0 else {
			fatalError("pthread_cancel error \(errno) from \(#file):\(#line)")
		}

		guard pthread_kill(_pt!, SIGUSR1) == 0 else {
			fatalError("pthread_kill error \(errno) from \(#file):\(#line)")
		}
	}

	internal func join() throws {

		// read the existing mode from memory
		var existingMode = mode.load()

		// validate this isn't already dead or joining
		guard existingMode != PThreadOperationMode.dead.rawValue && (existingMode & PThreadOperationMode.joining.rawValue == 0) else {
			throw InvalidModeError(mode:PThreadOperationMode(rawValue:existingMode))
		}

		// apply the existing value with the joining flag
		guard mode.compareExchangeWeak(expected:&existingMode, desired:existingMode | PThreadOperationMode.joining.rawValue) else {
			throw InvalidModeError(mode:PThreadOperationMode(rawValue:existingMode))
		}

		// join the pthread
		guard pthread_join(_pt!, nil) == 0 else {
			fatalError("pthread_join error \(errno) from \(#file):\(#line)")
		}
	}

	deinit {
		try? cancel()
		try? join()
	}
}

extension PThread {

	/// main function that handles the unwrapping of the logger before calling the main function.
	private static func pthreadMainWrapper(_ ptr:UnsafeMutableRawPointer) -> Never {
		var retainedValue:PThread.ContainedConfiguration? = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(configPtr).takeRetainedValue()
		
		let deallocator = retainedValue.getDeallocFunction()
		let workspacePtr = retainedValue.getAllocFunction()
		retainedValue = nil

		_cswiftslash_pthreads_main_f_run(ptr, { configPtr, workspacePtr in 
			// use an unretained value because the root function is retaining the configuration
			pthreadConfig.launchFuture.setSuccess()

			// run the configured task
			pthreadConfig.getRunFunction()(configPtr, workspacePtr)
			pthreadConfig.setResult(.success(()))
		}, { configPtr in
			// obtain the allocator function from the configuration and call it with the workspace pointer
			return Unmanaged<PThread.ContainedConfiguration>.fromOpaque(configPtr).takeUnretainedValue().getAllocFunction()()
		}, { configPtr, deallocateWorkspace in 
			// obtain the deallocator function from the configuration and call it with the workspace pointer
			Unmanaged<PThread.ContainedConfiguration>.fromOpaque(configPtr).takeRetainedValue().getDeallocFunction()(deallocateWorkspace)
			
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
		deinit {
			print("RESULT DEINIT")
		}
	}
	private final class ContainedError {
		internal let err:Swift.Error
		internal init(err:Swift.Error) {
			self.err = err
		}
		deinit {
			print("ERROR DEINIT")
		}
	}

	private final class Workspace {
		internal let launchFuture:Future
		internal let resultFuture:Future
		internal init(launchFuture:Future, resultFuture:Future) {
			self.launchFuture = launchFuture
			self.resultFuture = resultFuture
		}
		deinit {
			print("WORKSPACE DEINIT")
		}
	}

	/// this class is used to pass a logger to the pthread in a relatively swift-friedly way.
	private final class ContainedConfiguration {
		private let argumentPtr:UnsafeRawPointer?
		private let allocFunc:WorkspaceAllocator
		private let runFunc:WorkFunc
		private let deallocFunc:WorkspaceDeallocator
		private let resultFuture = Future()
		internal let launchFuture = Future()
		private enum Mode:UInt8 {
			case hasResult = 1
			case noResult = 0
		}
		internal init(arg:UnsafeRawPointer?, allocate:@escaping WorkspaceAllocator, work runFunc:@escaping WorkFunc, dealloc:@escaping WorkspaceDeallocator) {
			self.argumentPtr = arg
			self.allocFunc = allocate
			self.runFunc = runFunc
			self.deallocFunc = dealloc
			// self.sem = _cswiftslash_sem_fresh(0)
			var allowedSignals = sigset_t()
			sigemptyset(&allowedSignals)
			sigaddset(&allowedSignals, SIGUSR1)
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
		internal borrowing func getResultFuture() -> Future {
			return resultFuture
		}
		internal func getResult() async throws -> Result<Void, Error> {
			return try resultFuture.waitForResult()
		}
		deinit {
			print("CONFIGURATION DEINIT")
			fatalError("Configuration deinit")
		}
	}
}
