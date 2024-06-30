#if os(Linux)
import Glibc
#elseif os(macOS)
import Darwin
#endif

import __cswiftslash
import Logging

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
	#if os(Linux)
	private let pt_primitive:UnsafeMutablePointer<pthread_t>
	#elseif os(macOS)
	private let pt_primitive:UnsafeMutablePointer<pthread_t?>
	#endif

	internal struct PThreadOperationMode:OptionSet {
		internal let rawValue:UInt8

		/// this is the explicit value of the mode byte when the pthread is dead.
		internal static let dead: PThreadOperationMode = PThreadOperationMode(rawValue:0)

		/// this flag is enabled when the pthread is running.
		internal static let running = PThreadOperationMode(rawValue:1)

		/// this flag is enabled when the pthread has been sent a cancel signal.
		internal static let canceled = PThreadOperationMode(rawValue:1 << 1)
	}
	private var mode:_cswiftslash_atomic_uint8_t

	private let configuration:ContainedConfiguration

	internal init(logger:consuming Logger, _ f:@escaping (borrowing Logger) throws -> Void) throws {
		let newConf = PThread.ContainedConfiguration(logger, run:f)
		self.configuration = newConf
		let configPtr = Unmanaged.passRetained(newConf)
		#if os(Linux)
		let pthread = UnsafeMutablePointer<pthread_t>.allocate(capacity:1)
		guard pthread_create(pthread, nil, { Self.mainWrapper($0!) }, configPtr.toOpaque()) != 0 && pthread != nil else {
			_ = configPtr.takeRetainedValue()
			throw LaunchError()
		}
		#elseif os(macOS)
		let pthread = UnsafeMutablePointer<pthread_t?>.allocate(capacity:1)
		guard pthread_create(pthread, nil, { Self.mainWrapper($0) }, configPtr.toOpaque()) == 0, pthread.pointee != nil else {
			_ = configPtr.takeRetainedValue()
			throw LaunchError()
		}
		#endif
		self.pt_primitive = pthread
		self.mode = _cswiftslash_atomic_uint8_t()
		_cswiftslash_auint8_store(&mode, PThreadOperationMode.running.rawValue)
	}

	internal mutating func cancel() throws {
		var existingMode = _cswiftslash_auint8_load(&mode)
		// validate this isn't already canceled
		guard existingMode & PThreadOperationMode.canceled.rawValue == 0 else {
			throw InvalidModeError(mode:PThreadOperationMode(rawValue:existingMode))
		}

		// apply the existing value with the cancelled flag
		guard _cswiftslash_auint8_compare_exchange_weak(&mode, &existingMode, existingMode | PThreadOperationMode.canceled.rawValue) else {
			throw InvalidModeError(mode:PThreadOperationMode(rawValue:existingMode))
		}
		// fatalError("pthread_cancel error \(errno) from \(#file):\(#line)")
		// success, cancel the pthread
		#if os(Linux)
		guard pthread_cancel(pt_primitive.pointee) == 0 else {
			fatalError("pthread_cancel error \(errno) from \(#file):\(#line)")
		}
		#elseif os(macOS)
		guard pthread_cancel(pt_primitive.pointee!) == 0 else {
			fatalError("pthread_cancel error \(errno) from \(#file):\(#line)")
		}
		#endif
	}

	internal borrowing func waitForResult() async -> Result<Void, Error> {
		return await configuration.getResult()
	}

	deinit {
		// do any remaining cleanup
		var finalMode = mode
		let loadedMode = _cswiftslash_auint8_load(&finalMode)

		// if the pthread is running and it is not canceled, cancel it.
		if (loadedMode & PThreadOperationMode.running.rawValue != 0) && (loadedMode & PThreadOperationMode.canceled.rawValue == 0) {
			#if os(Linux)
			guard pthread_cancel(pt_primitive.pointee) == 0 else {
				fatalError("pthread_cancel error \(errno) from \(#file):\(#line)")
			}
			#elseif os(macOS)
			guard pthread_cancel(pt_primitive.pointee!) == 0 else {
				// fatalError("pthread_cancel error \(errno) from \(#file):\(#line)")
				return
			}
			#endif
		}

		#if os(Linux)
		var retPtr:UnsafeMutableRawPointer? = nil
		guard pthread_join(pt_primitive.pointee, &retPtr) == 0 else {
			fatalError("pthread_join error \(errno) from \(#file):\(#line)")
		}
		// _ = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(retPtr!).takeRetainedValue()
		#elseif os(macOS)
		var retPtr:UnsafeMutableRawPointer? = nil
		guard pthread_join(pt_primitive.pointee!, &retPtr) == 0 else {
			fatalError("pthread_join error \(errno) from \(#file):\(#line)")
		}
		// _ = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(retPtr!).takeRetainedValue()
		#endif
		
		pt_primitive.deallocate()
	}
}

extension PThread {

	/// main function that handles the unwrapping of the logger before calling the main function.
	private static func mainWrapper(_ ptr:UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {

		// this is the retaining variable for this entire function
		let config:PThread.ContainedConfiguration = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(ptr).takeRetainedValue()
		var logger = config.getLogger()
		let tid = pthread_self()
		logger[metadataKey:"pthread_id"] = "\(tid)"
		logger.debug("pthread launched")

		_cswiftslash_pthreads_main_f_run(Unmanaged.passUnretained(config).toOpaque(), { configPtr in 
			// use an unretained value because the root function is retaining the configuration
			let config = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(configPtr).takeUnretainedValue()
			do {
				// run the configured task
				try config.getRunFunction()(config.getLogger())
				// task complete. pass the success result to the future
				config.withFuture { f in
					_ = _cswiftslash_future_t_broadcast_res_val(f, 0, nil)
				}
			} catch let error {
				// task failed. pass the error result to the future
				config.withFuture { f in
					let result = Unmanaged.passRetained(PThread.ContainedError(err:error))
					guard _cswiftslash_future_t_broadcast_res_val(f, 0, result.toOpaque()) == true else {
						_ = result.takeRetainedValue()
						return
					}
					return
				}
			}
		}, { configPtr in
			// use an unretained value because the root function is retaining the configuration
			let config = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(configPtr).takeUnretainedValue()
			config.withFuture { f in
				_ = _cswiftslash_future_t_broadcast_cancel(f)
			}
		})
		
		return nil
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

	/// this class is used to pass a logger to the pthread in a relatively swift-friedly way.
	private final class ContainedConfiguration {
		private let logger:Logger
		private let runFunc:(borrowing Logger) throws -> Void
		private var result:Result<Void, Error>? = nil
		private var future:_cswiftslash_future_t = _cswiftslash_future_t()
		private enum Mode:UInt8 {
			case hasResult = 1
			case noResult = 0
		}
		internal init(_ logger:Logger, run runFunc:@escaping (borrowing Logger) throws -> Void) {
			self.logger = logger
			self.runFunc = runFunc
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
						returnResultPtr.pointee = nil
					}, { errPtr in 
						let error = Unmanaged<PThread.ContainedError>.fromOpaque(errPtr!).takeUnretainedValue().err
						returnResultPtr.pointee = .failure(error)
					}, {
						returnResultPtr.pointee = .success(())
					})
				}
				cont.resume(returning:getResult!)
			})
			
		}
		deinit {
			_cswiftslash_future_t_destroy(&future, { _ in return }, { errPtr in
				_ = Unmanaged<PThread.ContainedError>.fromOpaque(errPtr!).takeRetainedValue()
			})
		}
	}
}
