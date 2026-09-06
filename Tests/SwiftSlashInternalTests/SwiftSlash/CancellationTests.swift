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
import __cswiftslash_posix_helpers
import Foundation

extension Tag {
	@Tag internal static var swiftSlashCancellationTests:Self
}

extension SwiftSlashTests {
	@Suite("SwiftSlashCancellationTests", 
		.serialized,
		.tags(.swiftSlashCancellationTests)
	)
	struct SwiftSlashCancellationTests {

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

		/// polls a file path until it exists and is non-empty, or returns false after the timeout.
		private func waitForFileContents(_ path:String) async -> String? {
			for _ in 0..<100 {
				if let contents = try? String(contentsOfFile:path, encoding:.utf8) {
					let trimmed = contents.trimmingCharacters(in:.whitespacesAndNewlines)
					if trimmed.isEmpty == false {
						return trimmed
					}
				}
				try? await Task.sleep(for:.milliseconds(25))
			}
			return nil
		}

		@Test("SwiftSlashCancellationTests :: runSync(cancellationSignal:) behaves like runSync() when not cancelled",
			.timeLimit(.minutes(1))
		)
		func testRunSyncNormalPath() async throws {
			let randomInt = Int.random(in:0...Int.max)
			let result = try await Command(absolutePath:"/bin/echo", arguments:["hello world \(randomInt)"]).runSync(cancellationSignal:ChildProcess.defaultCancellationSignal)
			#expect(result.exit == .code(0))
			#expect(result.stdout.count == 1, "expected exactly one line of stdout")
			let line = String(bytes:result.stdout.first!, encoding:.utf8)
			#expect(line == "hello world \(randomInt)", "expected output to match input string")
			#expect(result.stderr.isEmpty, "expected no stderr output")
			#expect(result.succeeded == true)
		}

		@Test("SwiftSlashCancellationTests :: task cancellation terminates a running child with the default signal (SIGTERM)",
			.timeLimit(.minutes(1))
		)
		func testCancellationDefaultSignal() async throws {
			let process = ChildProcess(Command(absolutePath:"/bin/sleep", arguments:["30"]))
			let runTask = Task { () -> ChildProcess.Exit in
				try await process.run(cancellationSignal:ChildProcess.defaultCancellationSignal)
			}
			let running = await waitUntilRunning(process)
			guard case .running(let pid) = running else {
				Issue.record("process never reached the running state")
				runTask.cancel()
				return
			}
			runTask.cancel()
			do {
				_ = try await runTask.value
				Issue.record("expected CancellationError, but the run produced a result")
			} catch is CancellationError {
				// expected. the signal was SIGTERM.
			} catch {
				Issue.record("expected CancellationError, but got \(error)")
			}
			let finalState = await process.state
			guard case .reaped(let exit) = finalState else {
				Issue.record("expected the process to be reaped after cancellation, but got \(finalState)")
				return
			}
			#expect(exit == .signal(SIGTERM), "expected termination by SIGTERM, but the process exited with \(exit)")
			#expect(kill(pid, 0) == -1 && __cswiftslash_get_errno() == ESRCH, "child pid \(pid) must be fully gone from the process table (reaped, not a zombie)")
		}

		@Test("SwiftSlashCancellationTests :: task cancellation with SIGKILL terminates a child that ignores SIGTERM",
			.timeLimit(.minutes(1))
		)
		func testCancellationForcedKill() async throws {
			// this child installs a bare ignore handler for SIGTERM and loops forever, so only a forced kill can terminate it.
			let process = ChildProcess(Command(absolutePath:"/bin/sh", arguments:["-c", #"trap '' TERM; while true; do sleep 1; done"#]))
			let runTask = Task { () -> ChildProcess.Exit in
				try await process.run(cancellationSignal:SIGKILL)
			}
			let running = await waitUntilRunning(process)
			guard case .running(let pid) = running else {
				Issue.record("process never reached the running state")
				runTask.cancel()
				return
			}
			runTask.cancel()
			do {
				_ = try await runTask.value
				Issue.record("expected CancellationError, but the run produced a result")
			} catch is CancellationError {
				// expected. the signal was SIGKILL.
			} catch {
				Issue.record("expected CancellationError, but got \(error)")
			}
			let finalState = await process.state
			guard case .reaped(let exit) = finalState else {
				Issue.record("expected the process to be reaped after cancellation, but got \(finalState)")
				return
			}
			#expect(exit == .signal(SIGKILL), "expected termination by SIGKILL, but the process exited with \(exit)")
			#expect(kill(pid, 0) == -1 && __cswiftslash_get_errno() == ESRCH, "child pid \(pid) must be fully gone from the process table (reaped, not a zombie)")
		}

		@Test("SwiftSlashCancellationTests :: task cancellation before launch does not spawn a child",
			.timeLimit(.minutes(1))
		)
		func testCancellationBeforeLaunch() async throws {
			let process = ChildProcess(Command(absolutePath:"/bin/sleep", arguments:["30"]))
			// gate the run so the test can cancel deterministically before the launch begins.
			let gate = AsyncStream<Void>.makeStream()
			let runTask = Task { () -> ChildProcess.Exit in
				for await _ in gate.stream {
					break
				}
				return try await process.run(cancellationSignal:ChildProcess.defaultCancellationSignal)
			}
			runTask.cancel()
			gate.continuation.yield()
			gate.continuation.finish()
			do {
				_ = try await runTask.value
				Issue.record("expected CancellationError, but the run produced a result")
			} catch is CancellationError {
				// expected.
			} catch {
				Issue.record("expected CancellationError, but got \(error)")
			}
			#expect(await process.state == .initialized, "no child process should have been spawned")
		}

		@Test("SwiftSlashCancellationTests :: runSync(cancellationSignal:) terminates and reaps the child on task cancellation",
			.timeLimit(.minutes(1))
		)
		func testRunSyncCancellation() async throws {
			let pidFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("swiftslash-cancel-\(UUID().uuidString).pid")
			defer {
				try? FileManager.default.removeItem(at:pidFileURL)
			}
			let command = Command(absolutePath:"/bin/sh", arguments:["-c", #"echo $$ > "\#(pidFileURL.path)"; sleep 30"#])
			let runTask = Task { () -> Command.SyncResult in
				try await command.runSync(cancellationSignal:ChildProcess.defaultCancellationSignal)
			}
			guard let pidContents = await waitForFileContents(pidFileURL.path), let childPID = pid_t(pidContents), childPID > 0 else {
				Issue.record("child process never reported its pid")
				runTask.cancel()
				return
			}
			runTask.cancel()
			do {
				_ = try await runTask.value
				Issue.record("expected CancellationError, but the run produced a result")
			} catch is CancellationError {
				// expected.
			} catch {
				Issue.record("expected CancellationError, but got \(error)")
			}
			#expect(kill(childPID, 0) == -1 && __cswiftslash_get_errno() == ESRCH, "child pid \(childPID) must be fully gone from the process table (reaped, not a zombie)")
		}
	}
}
