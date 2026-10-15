/*
LICENSE MIT
copyright (c) tanner silva 2026. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  /
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/ 

*/

import Testing
@testable import SwiftSlash
import SwiftSlashFHHelpers
import __cswiftslash_posix_helpers
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension SwiftSlashTests {
	/// a launch's read side must terminate when there is nothing left to read.
	///
	/// a reader that retries an empty non-blocking descriptor instead of
	/// reporting `error_wouldblock` burns a cooperative thread at 100% cpu with
	/// no suspension point: it cannot observe cancellation, its launch's task
	/// group can never finish, and the child is therefore never reaped.
	@Suite("SwiftSlashReadTaskTermination",
		.serialized
	)
	struct SwiftSlashReadTaskTerminationTests {

		/// cpu time consumed by this process — the measurement that separates a
		/// parked reader from a retrying one.
		private func processUserCPU() -> Double {
			var usage = rusage()
			#if canImport(Darwin)
			guard getrusage(RUSAGE_SELF, &usage) == 0 else {
				return 0
			}
			#else
			// glibc exposes RUSAGE_SELF as `__rusage_who` while getrusage takes `__rusage_who_t`.
			guard getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage) == 0 else {
				return 0
			}
			#endif
			return Double(usage.ru_utime.tv_sec) + (Double(usage.ru_utime.tv_usec) / 1_000_000)
		}

		/// polls the process state until it reaches the running state, or returns the latest state after the timeout.
		private func waitUntilRunning(_ process:ChildProcess) async -> ChildProcess.State {
			for _ in 0..<100 {
				let state = await process.state
				switch state {
					case .running(_):
						return state
					default:
						break
				}
				try? await Task.sleep(for:.milliseconds(25))
			}
			return await process.state
		}

		/// polls for a child-created marker file. the child writes it only after
		/// its SIGTERM disposition is installed, so a test that cancels after the
		/// marker exists is racing nothing.
		private func waitForMarker(_ path:String) async -> Bool {
			for _ in 0..<200 {
				if FileManager.default.fileExists(atPath:path) {
					return true
				}
				try? await Task.sleep(for:.milliseconds(25))
			}
			return false
		}

		/// waits for a task to settle, but never longer than `seconds`.
		private func settled<T>(_ task:Task<T, any Error>, within seconds:Double) async -> Bool {
			await withTaskGroup(of:Bool.self) { group in
				group.addTask {
					_ = try? await task.value
					return true
				}
				group.addTask {
					try? await Task.sleep(for:.seconds(seconds))
					return false
				}
				let first = await group.next() ?? false
				if first == false {
					// the bound won: release the observing child so this scope can
					// exit, instead of waiting on a task that may never settle.
					task.cancel()
				}
				group.cancelAll()
				return first
			}
		}

		@Test("SwiftSlashReadTaskTermination :: a cancelled launch with a surviving silent child does not busy-wait on its stdout",
			.timeLimit(.minutes(1))
		)
		func cancelledLaunchWithSurvivingChildDoesNotBusyWait() async throws {
			let markerURL = FileManager.default.temporaryDirectory.appendingPathComponent("swiftslash-survivor-\(UUID().uuidString).marker")
			defer {
				try? FileManager.default.removeItem(at:markerURL)
			}
			// the child installs a bare ignore handler for SIGTERM and only then
			// creates the marker, so the cancellation below can never race the
			// trap installation. it writes nothing while it holds the pipe open:
			// an open, silent read descriptor is the state a reader must park in.
			let script = "trap '' TERM; : > '\(markerURL.path)'; while true; do sleep 1; done"
			let process = ChildProcess(Command(absolutePath:"/bin/sh", arguments:["-c", script]))
			let runTask = Task { () -> ChildProcess.Exit in
				try await process.run(cancellationSignal:ChildProcess.defaultCancellationSignal)
			}
			let running = await waitUntilRunning(process)
			guard case .running(let pid) = running else {
				Issue.record("process never reached the running state")
				runTask.cancel()
				return
			}
			guard await waitForMarker(markerURL.path) else {
				Issue.record("child never installed its SIGTERM disposition")
				_ = kill(pid, SIGKILL)
				return
			}
			runTask.cancel()

			// the reader was released by the cancellation; the child survives the
			// signal and stays silent, so there is nothing to drain. any cpu burned
			// in this window is the reader retrying an empty descriptor.
			let cpuBefore = processUserCPU()
			try? await Task.sleep(for:.milliseconds(1500))
			let cpuBurned = processUserCPU() - cpuBefore
			#expect(cpuBurned < 0.25, "reader busy-waited on an open, silent read pipe: \(cpuBurned)s of cpu time burned")

			// let the launch settle so the test leaves no child behind.
			_ = kill(pid, SIGKILL)
			#expect(await settled(runTask, within:5.0), "the launch never settled after the child was killed: the read task could not finish")
		}

		/// a direct child that exits immediately while a background survivor
		/// inherits its stdout leaves the read pipe open with no eof to observe.
		/// the launch must still settle — and reap the direct child — once the
		/// child is gone, rather than parking forever on a pipe end that only a
		/// survivor holds.
		@Test("SwiftSlashReadTaskTermination :: a launch whose child exits while a survivor holds the pipe still settles",
			.timeLimit(.minutes(1))
		)
		func launchSettlesWhenChildExitsWithSurvivorHoldingPipe() async throws {
			let markerURL = FileManager.default.temporaryDirectory.appendingPathComponent("swiftslash-survivor-pid-\(UUID().uuidString).marker")
			defer {
				try? FileManager.default.removeItem(at:markerURL)
			}
			// the shell forks a survivor that inherits stdout and stays silent,
			// records the survivor's pid, then exits at once. the direct child is
			// gone, but the pipe has no eof: nothing will ever write to it again.
			let script = "sleep 30 & echo $! > '\(markerURL.path)'; exit 0"
			let process = ChildProcess(Command(absolutePath:"/bin/sh", arguments:["-c", script]))
			let runTask = Task { () -> ChildProcess.Exit in
				try await process.run()
			}
			// recover the survivor's pid from the marker so this test can reap it.
			var survivorPID:pid_t = 0
			for _ in 0..<200 {
				if let contents = try? String(contentsOfFile:markerURL.path, encoding:.utf8),
					let parsed = pid_t(contents.trimmingCharacters(in:.whitespacesAndNewlines)) {
					survivorPID = parsed
					break
				}
				try? await Task.sleep(for:.milliseconds(25))
			}
			defer {
				if survivorPID > 0 {
					_ = kill(survivorPID, SIGKILL)
				}
			}
			#expect(survivorPID > 0, "the child never wrote its survivor pid to the marker")
			let didSettle = await settled(runTask, within:10.0)
			if !didSettle {
				// do not leave a parked launch behind for the rest of the suite.
				runTask.cancel()
			}
			#expect(didSettle, "run() never returned although the direct child exited and only a survivor held the pipe")
		}
	}
}