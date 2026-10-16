/*
LICENSE MIT
copyright (c) tanner silva 2026. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  / 
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/  

*/

import Synchronization
import __cswiftslash_posix_helpers
import SwiftSlashFIFO

/// Comprehensive tool for launching `Command`s.
/// - NOTE: When SwiftSlash launches a process, the launched process is referred to as a *child* process.
public actor ChildProcess {
	/// Thrown when the process interface is not in the expected state for the requested operation.
	public struct InvalidProcessStateError:Swift.Error {
		/// The state that was expected when the operation was requested.
		public let expectedState:State
		/// The actual state of the process when the operation was requested.
		public let actualState:State
	}
	
	/// Thrown when a signal code failed send to the child process.
	public enum SignalError:Swift.Error {
		/// Thrown when the the host system kernel is unsuccessful at sending the signal to the child process.
		/// - Parameter errno: The system `errno` that was returned in correspondence with the failure.
		case systemSignalError(errno:Int32)
		/// Thrown when the process was found to be at an incorrect lifecycle state to send a signal. This means the process has either not launched, or has already exited.
		case invalidState(InvalidProcessStateError)
	}

	/// The set of processes a signal addresses.
	public enum SignalRecipient:Sendable {
		/// The direct child only.
		case process
		/// The child and everything sharing its process group. This is the
		/// default, and it is the same scope the cancellation path uses.
		///
		/// The scope a launch can actually reach is bounded by the child's
		/// ``ProcessGroup``: a child placed in its own group takes its whole
		/// tree down with it, while a child that leads no group of its own has
		/// no group this launch can address — signalling that group would reach
		/// the caller's own processes — so the signal goes to the child's pid
		/// alone.
		case processGroup
	}

	/// Represents the various states that a child process may be in while going through its lifecycle.
	public enum State:Sendable {
		/// The process interface is initialized, but not yet launched.
		case initialized
		/// The process interface is in the process of launching. a `pid_t` is not yet available, additionally, the launch process may fail instead of returning a `pid_t`.
		case launching
		/// The process is running as the current pid_t value.
		case running(pid_t)
		/// The process has been reaped with the specified result outcome.
		case reaped(Exit)
	}

	/// Represents the result of a process exit after it has been reaped with `waitpid()`.
	public enum Exit:Sendable {
		/// The process exited normally with the specified exit code.
		case code(Int32)
		/// The process was terminated by a signal with the specified signal code.
		case signal(Int32)
	}

	/// The current operating state of the process. This is a primary pillar of logic for the ChildProcess functionality.
	public private(set) var state:State = .initialized

	/// The command associated with the child process instance.
	public let command:Command

	/// The data channels that will be launched.
	private let dataChannels:[Int32:DataChannel]

	/// Where this child sits in the process-group hierarchy. This decides which
	/// signals reach the child and whether it outlives its launch.
	private let processGroup:ProcessGroup

	/// Initialize a process interface with a command and a set of data channels.
	/// - Parameters:
	/// 	- command: The command to execute.
	/// 	- processGroup: Where the child is placed in the process-group hierarchy, or `nil` to resolve it from the enclosing launch (see ``ProcessGroup``). A process spawned by a launch joins the group of the launch it is already in, so an outer teardown cascades; a process nobody launched leads its own group.
	/// 	- dataChannels: Data channels to bind to the child process. The keys of this dictionary are the file handle values that will be assigned to the child process (values of `STDOUT_FILENO`, `STDIN_FILENO`, etc).
	public init(_ command:Command,
		processGroup:ProcessGroup? = nil,
		dataChannels:[Int32:DataChannel] = [
		STDOUT_FILENO : .write(.toParentProcess(stream:.init(), separator:[0x0A])),
		STDERR_FILENO : .write(.toParentProcess(stream:.init(), separator:[0x0A])),
		STDIN_FILENO : .read(.fromParentProcess(stream:.init()))
	]) {
		self.command = command
		self.processGroup = processGroup ?? ProcessLogistics.automaticPlacement
		self.dataChannels = dataChannels
	}
	
	/// Access a data stream to the process of a specified file handle value.
	/// - Returns: The data channel for the specified file handle, or `nil` if none was found.
	public nonisolated subscript(channel fh:Int32) -> DataChannel? {
		get {
			return dataChannels[fh]
		}
	}
	
	/// Convenience subscript for accessing the data channel that is already known to be a writable stream.
	/// - WARNING: This subscript will throw a fatal error (crashing the parent process) if the data channel is found to be a ``SwiftSlash/DataChannel/ChildRead`` stream.
	/// - Returns: The writing interface to the child process, or `nil` if the file handle is not configured.
	public nonisolated subscript(writer fh:Int32) -> DataChannel.ChildWrite? {
		get {
			switch dataChannels[fh] {
				case .write(let config):
					return config
				case .read(_):
					fatalError("SwiftSlash critical error :: attempted to access a writable data stream but the data channel is configured as a readable stream. \(#file):\(#line)")
				case .none:
					return nil
			}
		}
	}
	/// Convenience subscript for accessing the data channel that is already known to be a readable stream.
	/// - WARNING: This subscript will throw a fatal error (crashing the parent process) if the data channel is found to be a ``SwiftSlash/DataChannel/ChildWrite`` stream.
	/// - Returns: The reading interface bound to the child process, or `nil` if the file handle is not configured.
	public nonisolated subscript(reader fh:Int32) -> DataChannel.ChildRead? {
		get {
			switch dataChannels[fh] {
				case .read(let config):
					return config
				case .write(_):
					fatalError("SwiftSlash critical error :: attempted to access a readable data stream but the data channel is configured as a writable stream. \(#file):\(#line)")
				case .none:
					return nil
			}
		}
	}
	
	/// The signal that a cancellable run path sends to the child process when the calling task is cancelled before the process exits.
	public static let defaultCancellationSignal:Int32 = SIGTERM

	/// Launches the child process by executing the configured command with the configured data channels.
	/// This function will not return until the child process exits.
	/// - Returns: The exit or signal code that the child process exited with.
	public func run() async throws -> Exit {
		return try await runInternal(cancellationSignal:nil)
	}

	/// Launches the child process by executing the configured command with the configured data channels.
	/// This function will not return until the child process exits.
	/// - Parameter signal: The signal code that is sent to the child process if the calling task is cancelled before the process exits. The target of the signal is decided by the child's ``ProcessGroup``: a child placed in its own group is signalled as a group, so the whole tree goes down with it, while a child that leads no group is signalled as a single pid. cancellation of the calling task will also cause this function to throw `CancellationError` (after the child process has been signaled and reaped).
	/// - Returns: The exit or signal code that the child process exited with.
	public func run(cancellationSignal signal:Int32) async throws -> Exit {
		return try await runInternal(cancellationSignal:signal)
	}

	private func runInternal(cancellationSignal:Int32?) async throws -> Exit {
		// check the current state of the process. 
		switch state {
			case .initialized:
				// the caller has already cancelled their task before the launch began. do not spawn a child process.
				try Task.checkCancellation()

				// the process has not been launched yet so we may proceed with the launch.
				state = .launching

				// the pid of the launched process, readable from the synchronous, nonisolated cancellation handler.
				let cancellationKillPID:Atomic<Int32> = .init(0)
				// set to true when a signal has been sent to the child process as the direct result of task cancellation.
				let didSignalOnCancellation:Atomic<Bool> = .init(false)

				// the placement decides what this launch's teardown can address.
				// it is read once, before the launch, so the synchronous
				// nonisolated cancellation handler below can capture a plain
				// value rather than reaching back into the actor.
				let teardownPlacement = processGroup

				return try await withTaskCancellationHandler {
					try await withThrowingTaskGroup(of:Void.self) { tg in
						// create a launch package.
						let launchPackage = ProcessLogistics.LaunchPackage(
							exe:command.executable,
							arguments:command.arguments,
							workingDirectory:command.workingDirectory,
							env:command.environment,
							processGroup:processGroup,
							dataChannels:dataChannels
						)
						
						// launch the package.
						let preapredPackage = try await ProcessLogistics.launch(package:launchPackage)
						
						// update state
						state = .running(preapredPackage.launchedPID)

						// expose the pid to the cancellation handler and cover the case where the task was cancelled during the launch. the target of the signal is decided by the child's placement: a child that leads its own process group is signalled as a group so the whole tree goes down, and any other placement is signalled as a pid.
						if let signal = cancellationSignal {
							cancellationKillPID.store(preapredPackage.launchedPID, ordering:.releasing)
							if Task.isCancelled {
								_ = kill(teardownPlacement.signalTarget(pid:preapredPackage.launchedPID), signal)
								didSignalOnCancellation.store(true, ordering:.releasing)
							}
						}
						
						// launch the reader and writer loops that are associated with the running process.
						for curWrite in preapredPackage.writeTasks {
							curWrite.launch(taskGroup:&tg)
						}
						for curRead in preapredPackage.readTasks {
							curRead.launch(taskGroup:&tg)
						}
						
						// the io loops are capped only by their channels' finish
						// futures, which the event trigger completes on eof. a
						// process that survives the child can keep a pipe end open,
						// so no eof ever arrives and a loop parks on a stream that
						// nothing can end. the child's own exit must therefore cap
						// the channels too, and it has to be watched while the loops
						// are still running — the reap below runs only after them.
						//
						// this watcher is a member of the same group, so waitForAll
						// cannot return before it has finished and deregistered. the
						// reap then registers a monitor for the same pid, and those
						// two registrations must never overlap: process monitors are
						// held per pid, so a second registration would replace this
						// one's entry and strand its waiter.
						let cappableWriteFutures = preapredPackage.writeTasks.map({ $0.terminationFuture })
						let cappableReadFutures = preapredPackage.readTasks.map({ $0.terminationFuture })
						let watchedPID = preapredPackage.launchedPID
						let watchingTrigger = preapredPackage.eventTrigger
						tg.addTask {
							let exitFIFO:FIFO<Int, Never> = try! .init()
							let exitConsumer = exitFIFO.makeAsyncConsumer()
							do {
								try await ProcessLogistics.registerProcessExitMonitor(watchedPID, on:watchingTrigger, fifo:exitFIFO)
							} catch {
								// no kernel process monitor (an old kernel, or fd
								// exhaustion). the reap below falls back to polling,
								// but this cap cannot: capping before the child is
								// known to be gone would truncate live output. the
								// loops keep their pre-existing behaviour here.
								return
							}
							// suspend until the child exits. this suspension survives
							// task cancellation: the trigger's polling thread is
							// independent of the calling task.
							_ = await exitConsumer.next(whenTaskCancelled:.noAction)
							await ProcessLogistics.deregisterProcessExitMonitor(watchedPID, on:watchingTrigger)
							// the child is gone. cap every channel that its own eof
							// has not already ended, so a stream a survivor holds
							// open can still finish. a channel that already has a
							// result is left to its eof path, and the drain loop
							// that follows a cap reads out whatever the child left
							// behind in the pipe.
							for curFuture in cappableWriteFutures where curFuture.hasResult() == false {
								_ = try? curFuture.setSuccess(())
							}
							for curFuture in cappableReadFutures where curFuture.hasResult() == false {
								_ = try? curFuture.setSuccess(())
							}
						}

						// wait for the io loops to wind down. the group is cancelled with the calling task, so this can throw. the child process must still be reaped regardless of the outcome.
						let waitOutcome:Result<Void, any Error>
						do {
							try await tg.waitForAll()
							waitOutcome = .success(())
						} catch {
							waitOutcome = .failure(error)
						}

						// reap the running process.
						let exit:Exit
						switch await preapredPackage.launchedPID.waitPIDAsync(on:preapredPackage.eventTrigger) {
							case .exited(let exitCode):
								state = .reaped(.code(exitCode))
								exit = .code(exitCode)
							case .signaled(let sigCode):
								state = .reaped(.signal(sigCode))
								exit = .signal(sigCode)
							case .failed(let err):
								throw ReapError(errnoValue:err)
						}

						// surface cancellation to the caller when the process was terminated on their behalf. otherwise, propagate the io outcome.
						switch waitOutcome {
							case .success:
								if didSignalOnCancellation.load(ordering:.acquiring) {
									throw CancellationError()
								}
								return exit
							case .failure(let error):
								if didSignalOnCancellation.load(ordering:.acquiring) || Task.isCancelled {
									throw CancellationError()
								}
								throw error
						}
					}
				} onCancel: {
					let pid = cancellationKillPID.load(ordering:.acquiring)
					guard pid > 0, let signal = cancellationSignal else {
						return
					}
					_ = kill(teardownPlacement.signalTarget(pid:pid), signal)
					didSignalOnCancellation.store(true, ordering:.releasing)
				}
			default:
				// the process has already been launched so we cannot proceed with the launch.
				throw InvalidProcessStateError(expectedState:.initialized, actualState:state)
		}
	}
	
	/// Send a signal to the child process.
	/// - Parameters:
	/// 	- code: The signal code to send to the child process.
	/// 	- recipient: The set of processes the signal addresses. The default is ``SignalRecipient/processGroup``, which is the same scope the cancellation path uses. Pass ``SignalRecipient/process`` to address the direct child alone.
	/// - Throws: `SignalError` is thrown if the process is not running, or if the kernel refuses the signal.
	public func signal(_ code:Int32, to recipient:SignalRecipient = .processGroup) throws(SignalError) {
		switch state {
			case .running(let pid):
				let target:pid_t
				switch recipient {
					case .process:
						target = pid
					case .processGroup:
						target = processGroup.signalTarget(pid:pid)
				}
				let killReturnValue = kill(target, code)
				guard killReturnValue == 0 else {
					throw .systemSignalError(errno:__cswiftslash_get_errno())
				}
			default:
				throw .invalidState(InvalidProcessStateError(expectedState:.running(0), actualState:state))
		}
	}
}

extension ChildProcess {
	/// Where a spawned child sits in the process-group hierarchy. This decides
	/// which signals reach the child and whether it outlives its launch, so it
	/// is part of the launch contract rather than a launch detail.
	public enum ProcessGroup:Sendable {
		/// The child leads a new process group (`pgid == its pid`). A group
		/// signal aimed at this launch cascades through the child's whole tree,
		/// and the caller's own group is never touched. This is the placement
		/// used when no enclosing launch is detected.
		case own
		/// The child joins the caller's process group. The caller's group signal
		/// reaches the child and its tree. The child leads no group of its own,
		/// so this launch's own teardown signals the child's pid rather than a
		/// group: the group-scoped teardown belongs to whoever owns that group,
		/// which is an enclosing launch or the terminal a top-level process was
		/// started from. This placement is resolved automatically for a process
		/// that was itself spawned by a launch.
		case inherited
		/// The child starts a new session (`setsid(2)`), so it leads its own
		/// group and session. It survives the launch's teardown and no group
		/// signal can reach it. Detachment is always explicit.
		case detached
	}
}

extension ChildProcess.ProcessGroup {
	/// The placement code the spawn helper expects. Expressed through the
	/// imported C enumeration so the numbers exist in exactly one place.
	internal var spawnMode:Int32 {
		switch self {
			case .own:
				return Int32(__cswiftslash_pgroup_mode_own.rawValue)
			case .inherited:
				return Int32(__cswiftslash_pgroup_mode_inherited.rawValue)
			case .detached:
				return Int32(__cswiftslash_pgroup_mode_detached.rawValue)
		}
	}

	/// The pid value that addresses exactly the processes this placement makes a
	/// launch responsible for, when that launch sends a signal.
	///
	/// A child that leads its own group is reachable as a group: `kill(-pid)`
	/// cascades through the child's whole tree. A child that does not lead a
	/// group is reachable only as a pid — an `.inherited` child leads no group of
	/// its own, so the group-scoped teardown belongs to whoever owns that group
	/// (an enclosing launch, or the terminal a top-level process was started
	/// from), and a `.detached` child is deliberately out of reach of a group
	/// signal. Signalling the negated pid for either of those would address a
	/// process group that does not exist, so the signal would silently fail to
	/// arrive at all.
	internal func signalTarget(pid:pid_t) -> pid_t {
		switch self {
			case .own:
				return -pid
			case .inherited, .detached:
				return pid
		}
	}
}

extension ChildProcess {
	/// Convenience variable that returns access to the stdin stream of the process.
	public nonisolated var stdin:DataChannel.ChildRead.ParentWrite {
		get {
			switch self[reader:STDIN_FILENO] {
				case .fromParentProcess(stream:let strm):
					return strm
				default:
					fatalError("SwiftSlash ChildProces fatal error :: STDIN_FILENO has a non-standard configuration, therefore, the convenience variables cannot be used. This is a user error. \(#file):\(#line)")
			}
		}
	}
	/// Convenience variable that returns access to the stdout stream of the process.
	public nonisolated var stdout:DataChannel.ChildWrite.ParentRead {
		get {
			switch self[writer:STDOUT_FILENO] {
				case .toParentProcess(stream:let strm, separator:_):
					return strm
				default:
					fatalError("SwiftSlash ChildProces fatal error :: STDOUT_FILENO has a non-standard configuration, therefore, the convenience variables cannot be used. This is a user error. \(#file):\(#line)")
			}
		}
	}
	/// Convenience variable that returns access to the stderr stream of the process.
	public nonisolated var stderr:DataChannel.ChildWrite.ParentRead {
		get {
			switch self[writer:STDERR_FILENO] {
				case .toParentProcess(stream:let strm, separator:_):
					return strm
				default:
					fatalError("SwiftSlash ChildProces fatal error :: STDERR_FILENO has a non-standard configuration, therefore, the convenience variables cannot be used. This is a user error. \(#file):\(#line)")
			}
		}
	}
}

extension ChildProcess.Exit:Hashable, Equatable, CustomDebugStringConvertible {
	public static func == (lhs:ChildProcess.Exit, rhs:ChildProcess.Exit) -> Bool {
		switch (lhs, rhs) {
			case (.code(let lhsExitCode), .code(let rhsExitCode)):
				return lhsExitCode == rhsExitCode
			case (.signal(let lhsSignal), .signal(let rhsSignal)):
				return lhsSignal == rhsSignal
			default:
				return false
		}
	}
	public func hash(into hasher:inout Hasher) {
		switch self {
			case .code(let exitCode):
				hasher.combine(0)
				hasher.combine(exitCode)
			case .signal(let sig):
				hasher.combine(1)
				hasher.combine(sig)
		}
	}
	public var debugDescription: String {
		switch self {
			case .code(let exitCode):
				return "ChildProcess.Exit.exited(\(exitCode))"
			case .signal(let sigCode):
				return "ChildProcess.Exit.signaled(\(sigCode))"
		}
	}
}

extension ChildProcess.State:Hashable, Equatable {
	public static func == (lhs: ChildProcess.State, rhs: ChildProcess.State) -> Bool {
		switch (lhs, rhs) {
			case (.initialized, .initialized):
				return true
			case (.launching, .launching):
				return true
			case (.running(let lhsPID), .running(let rhsPID)):
				return lhsPID == rhsPID
			case (.reaped(let lhsResult), .reaped(let rhsResult)):
				return lhsResult == rhsResult
			default:
				return false
		}
	}
	public func hash(into hasher: inout Hasher) {
		switch self {
			case .initialized:
				hasher.combine(0)
			case .launching:
				hasher.combine(1)
			case .running(let pid):
				hasher.combine(2)
				hasher.combine(pid)
			case .reaped(let result):
				hasher.combine(3)
				hasher.combine(result)
		}
	}
}
