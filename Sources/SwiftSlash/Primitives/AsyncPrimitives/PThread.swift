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
	internal struct InvalidModeError:Swift.Error {}

	/// main function that handles the unwrapping of the logger before calling the main function.
	private static func mainWrapper(_ ptr:UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
		let unmanaged = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(ptr)
		var logger = unmanaged.takeUnretainedValue().getLogger()
		let tid = pthread_self()
		logger[metadataKey:"pthread_id"] = "\(tid)"
		logger.debug("pthread launched")
		do {
			try unmanaged.takeUnretainedValue().getRunFunction()(logger)
		} catch is CancellationError {
			logger.error("pthread canceled")
		} catch {
			logger.error("pthread error: \(error)")
		}
		pthread_exit(unmanaged.toOpaque())
	}

	/// the pthread primitive.
	#if os(Linux)
	private let pt_primitive:UnsafeMutablePointer<pthread_t>
	#elseif os(macOS)
	private let pt_primitive:UnsafeMutablePointer<pthread_t?>
	#endif

	internal struct PThreadOperationMode:OptionSet {
		internal let rawValue:UInt8
		internal static let running = PThreadOperationMode(rawValue:1)
		internal static let canceled = PThreadOperationMode(rawValue:1 << 1)
		internal static let joining = PThreadOperationMode(rawValue:2 << 1)
	}
	private var mode:_cswiftslash_atomic_uint8_t

	internal init(logger:consuming Logger, _ f:@escaping (borrowing Logger) throws -> Void) throws {
		let configPtr = Unmanaged.passRetained(PThread.ContainedConfiguration(logger, run:f))
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

	internal consuming func cancel() throws {
		infiniteLoop: repeat {
			// check existing mode
			var existingMode = _cswiftslash_auint8_load(&mode)
			switch existingMode {

			case PThreadOperationMode.running.rawValue:
				// running mode, try to set to canceled mode
				guard _cswiftslash_auint8_compare_exchange_weak(&mode, &existingMode, existingMode | PThreadOperationMode.canceled.rawValue) else {
					// mode changed, loop again to check new mode
					continue infiniteLoop
				}
			default:
				throw InvalidModeError()
			}

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

		} while Task.isCancelled == false
	}

	deinit {
		#if os(Linux)
		var retPtr:UnsafeMutableRawPointer? = nil
		guard pthread_join(pt_primitive.pointee, &retPtr) == 0 else {
			fatalError("pthread_join error \(errno) from \(#file):\(#line)")
		}
		_ = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(retPtr!).takeRetainedValue()
		pt_primitive.deallocate()
		#elseif os(macOS)
		var retPtr:UnsafeMutableRawPointer? = nil
		guard pthread_join(pt_primitive.pointee!, &retPtr) == 0 else {
			fatalError("pthread_join error \(errno) from \(#file):\(#line)")
		}
		_ = Unmanaged<PThread.ContainedConfiguration>.fromOpaque(retPtr!).takeRetainedValue()
		pt_primitive.deallocate()
		#endif
	}
}

extension PThread {
	/// this class is used to pass a logger to the pthread in a relatively swift-friedly way.
	internal final class ContainedConfiguration {
		private let logger:Logger
		private let runFunc:(borrowing Logger) throws -> Void
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
	}
}
