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
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension SwiftSlashTests {
	/// a launch owns its child's process group, and every descendant the child
	/// is responsible for must be reachable by the one signal the launch sends.
	///
	/// the machinery for a single level already exists: the child is placed in
	/// its own group and teardown signals `kill(-pid)`. it fails at exactly one
	/// point — a child that spawns *through swiftslash* runs the same spawn
	/// path, so it forms a second group the outer signal cannot reach, and the
	/// grandchild is reparented and keeps working after the caller reported
	/// failure. these tests drive that shape with a real second process.
	///
	/// liveness is observed in-process (`kill(pid, 0)` + `errno == ESRCH`) and
	/// never through `ps`/`pgrep`, so an assertion means the same thing on
	/// macOS and on linux.
	@Suite("SwiftSlashProcessGroup",
		.serialized
	)
	struct SwiftSlashProcessGroupTests {

		/// thrown when the fixture cannot be driven at all, as opposed to when
		/// an assertion about its behaviour fails.
		enum FixtureError:Swift.Error {
			/// the spawner fixture binary was not found next to the test products.
			case spawnerBinaryMissing([String])
			/// the launch never reached the running state.
			case launchNeverRan
			/// the fixture never published its direct child's pid.
			case markerNeverWritten(String)
			/// the fixture published fewer pid levels than the requested depth.
			case markerIncomplete(expected:Int, got:Int)
		}

		// MARK: - fixture location

		/// the spawner fixture, resolved relative to this source file so the
		/// suite works from any working directory. every layout swiftpm has
		/// used for this package is probed; an absent binary is a loud failure
		/// rather than a skipped suite, because a green run that asserted
		/// nothing is worse than a red one.
		static let spawnerPath:String = {
			let sourceComponents = #filePath.split(separator:"/")
			let packageRoot = "/" + sourceComponents.dropLast(4).joined(separator:"/")
			let candidates = [
				"\(packageRoot)/.build/debug/SwiftSlashTestSpawner",
				"\(packageRoot)/.build/out/Products/Debug/SwiftSlashTestSpawner",
				"\(packageRoot)/.build/release/SwiftSlashTestSpawner",
				"\(packageRoot)/.build/out/Products/Release/SwiftSlashTestSpawner",
			]
			for candidate in candidates {
				if FileManager.default.isExecutableFile(atPath:candidate) {
					return candidate
				}
			}
			return ""
		}()

		// MARK: - process observation (in-process, portable)

		/// true when the pid no longer exists at all. a zombie still answers
		/// `kill(pid, 0)`, which is why reaping is asserted separately.
		private func pidIsGone(_ pid:pid_t) -> Bool {
			if kill(pid, 0) == 0 {
				return false
			}
			return __cswiftslash_get_errno() == ESRCH
		}

		/// polls for a pid's disappearance, bounded.
		private func waitForExit(of pid:pid_t, within duration:Duration) async -> Bool {
			let deadline = ContinuousClock.now.advanced(by:duration)
			while ContinuousClock.now < deadline {
				if pidIsGone(pid) {
					return true
				}
				try? await Task.sleep(for:.milliseconds(25))
			}
			return pidIsGone(pid)
		}

		/// polls the process state until it reaches the running state, or
		/// returns the latest state after the timeout.
		private func waitUntilRunning(_ process:ChildProcess) async -> ChildProcess.State {
			for _ in 0..<200 {
				let state = await process.state
				if case .running = state {
					return state
				}
				try? await Task.sleep(for:.milliseconds(25))
			}
			return await process.state
		}

		/// waits for a task to settle, but never longer than `seconds`.
		private func settled(_ task:Task<ChildProcess.Exit, any Error>, within seconds:Double) async -> Bool {
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
					// the bound won: release the observing child so this scope
					// can exit, instead of waiting on a task that may never
					// settle.
					task.cancel()
				}
				group.cancelAll()
				return first
			}
		}

		/// reads every pid the fixture chain has published so far. each level
		/// appends its direct child's pid.
		///
		/// THE ORDER IS NOT GUARANTEED. two processes append, and a level that has
		/// already published its child can be overtaken by the line its own parent
		/// is about to write. treat the result as a SET and identify pids by their
		/// relationship (`getpgid`/`getsid`), never by index, unless the chain is
		/// exactly one level deep.
		private func markerPIDs(_ path:String, expecting count:Int) async -> [pid_t] {
			for _ in 0..<400 {
				if let contents = try? String(contentsOfFile:path, encoding:.utf8) {
					let pids = contents
						.split(separator:"\n")
						.compactMap { pid_t($0.trimmingCharacters(in:.whitespaces)) }
					if pids.count >= count {
						return pids
					}
				}
				try? await Task.sleep(for:.milliseconds(25))
			}
			return []
		}

		// MARK: - driving the fixture

		/// the observed result of one fixture run.
		struct SpawnerRun {
			/// the marker the chain appended its pids to.
			let markerPath:String
			/// where the fixture reported its enclosing launch, or "" when it was not
			/// asked to report one.
			let identityPath:String
			/// the pid of the fixture process the launch created.
			let outerPID:pid_t
			/// the pid chain, outermost first. the last element is the leaf.
			let recordedPIDs:[pid_t]
			/// the launch that owns the fixture, still running. the tests decide
			/// when to cancel it, so they can assert on the placement the
			/// fixture established before the teardown signal is sent.
			let launchTask:Task<ChildProcess.Exit, any Error>
		}

		/// launches the spawner fixture and waits for it to publish `depth + 1`
		/// pid levels. the teardown is deliberately NOT performed here: the
		/// tests assert on the placement the fixture established before the
		/// signal is sent, which is what makes them tests of the mechanism
		/// rather than of the outcome.
		private func startSpawnerFixture(
			mode:String = "stay",
			depth:Int = 0,
			placement:String? = nil,
			childPlacement:String? = nil,
			closeFD3:Bool = false,
			blockingFD3:Bool = false,
			identityReport:Bool = false
		) async throws -> SpawnerRun {
			guard Self.spawnerPath.isEmpty == false else {
				throw FixtureError.spawnerBinaryMissing([
					"\(#filePath)",
				])
			}
			let markerPath = FileManager.default.temporaryDirectory
				.appendingPathComponent("swiftslash-pgroup-\(UUID().uuidString).marker")
				.path
			let identityPath = FileManager.default.temporaryDirectory
				.appendingPathComponent("swiftslash-pgroup-\(UUID().uuidString).identity")
				.path

			var arguments = [
				"--self=\(Self.spawnerPath)",
				"--mode=\(mode)",
				"--marker=\(markerPath)",
				"--depth=\(depth)",
			]
			if let placement {
				arguments.append("--placement=\(placement)")
			}
			if let childPlacement {
				arguments.append("--child-placement=\(childPlacement)")
			}
			if closeFD3 {
				arguments.append("--close-fd3")
			}
			if blockingFD3 {
				arguments.append("--blocking-fd3")
			}
			if identityReport {
				arguments.append("--identity=\(identityPath)")
			}

			let process = ChildProcess(Command(
				absolutePath:Path(Self.spawnerPath),
				arguments:arguments,
				environment:CurrentEnvironment.environmentVariables()
			))
			let runTask = Task { () -> ChildProcess.Exit in
				try await process.run(cancellationSignal:ChildProcess.defaultCancellationSignal)
			}
			let running = await waitUntilRunning(process)
			guard case .running(let outerPID) = running else {
				runTask.cancel()
				_ = await settled(runTask, within:5.0)
				throw FixtureError.launchNeverRan
			}

			let recordedPIDs = await markerPIDs(markerPath, expecting:depth + 1)
			guard recordedPIDs.count >= depth + 1 else {
				runTask.cancel()
				_ = await settled(runTask, within:5.0)
				_ = kill(outerPID, SIGKILL)
				throw FixtureError.markerIncomplete(expected:depth + 1, got:recordedPIDs.count)
			}

			return SpawnerRun(
				markerPath:markerPath,
				identityPath:identityReport ? identityPath : "",
				outerPID:outerPID,
				recordedPIDs:recordedPIDs,
				launchTask:runTask
			)
		}

		/// the teardown under test: cancel the awaiting task, which sends this
		/// launch's teardown signal to exactly what its placement makes it
		/// responsible for. returns whether the launch settled within its bound.
		private func cancelLaunch(_ run:SpawnerRun) async -> Bool {
			run.launchTask.cancel()
			return await settled(run.launchTask, within:10.0)
		}

		/// removes the marker and guarantees nothing the fixture started is left
		/// running, whatever the assertion outcome was.
		private func cleanUp(_ run:SpawnerRun) {
			run.launchTask.cancel()
			for pid in run.recordedPIDs {
				_ = kill(pid, SIGKILL)
			}
			_ = kill(run.outerPID, SIGKILL)
			try? FileManager.default.removeItem(atPath:run.markerPath)
			if run.identityPath.isEmpty == false {
				try? FileManager.default.removeItem(atPath:run.identityPath)
			}
		}

		/// launches `/bin/sh -c <script>` and returns the shell's pid. this is
		/// the shape where the interesting processes are NOT the direct child:
		/// a shell that forks a background job defers signals and keeps its job
		/// in its own process group.
		private func launchShell(_ script:String) async throws -> (process:ChildProcess, runTask:Task<ChildProcess.Exit, any Error>, shellPID:pid_t) {
			let process = ChildProcess(Command(absolutePath:"/bin/sh", arguments:["-c", script]))
			let runTask = Task { () -> ChildProcess.Exit in
				try await process.run()
			}
			let running = await waitUntilRunning(process)
			guard case .running(let shellPID) = running else {
				runTask.cancel()
				throw FixtureError.launchNeverRan
			}
			return (process, runTask, shellPID)
		}

		/// makes a unique marker path for a test, and the cleanup for it.
		private func uniqueMarkerPath() -> String {
			FileManager.default.temporaryDirectory
				.appendingPathComponent("swiftslash-pgroup-\(UUID().uuidString).marker")
				.path
		}

		// MARK: - the escape this release closes

		/// the shape that produced arc's orphan: a launch whose child is itself
		/// a swift process, signalled from the outside. with the nested launch
		/// placed in the caller's group, the grandchild dies with it.
		@Test("SwiftSlashProcessGroup :: a nested launch dies with its parent's group signal",
			.timeLimit(.minutes(1))
		)
		func nestedLaunchDiesWithParentGroupSignal() async throws {
			let run = try await startSpawnerFixture(mode:"stay", depth:0, placement:"inherited")
			defer { cleanUp(run) }
			try #require(run.recordedPIDs.count == 1, "the fixture recorded \(run.recordedPIDs.count) pid levels, expected exactly one")
			let grandchildPID = run.recordedPIDs[0]

			// pin the MECHANISM, not just the outcome: the grandchild has to be
			// in the outer launch's group BEFORE the signal is sent, otherwise
			// this test would also pass if the grandchild died for some
			// unrelated reason.
			let grandchildGroup = getpgid(grandchildPID)
			#expect(grandchildGroup == run.outerPID,
				"the nested launch was placed in group \(grandchildGroup), expected the outer launch's group \(run.outerPID)")

			let didSettle = await cancelLaunch(run)
			#expect(didSettle, "the outer launch never settled after its group signal")
			let gone = await waitForExit(of:grandchildPID, within:.seconds(5))
			#expect(gone, "the nested launch survived its parent's group signal — pid \(grandchildPID) is still alive")
		}

		/// the trade-off, stated rather than left implicit. an `.own` nested
		/// launch leads its own process group, so the outer launch's group
		/// signal cannot reach it and it outlives its parent. this is the
		/// behaviour a nested launch has to opt out of, and it is why the
		/// automatic resolution later in this suite exists.
		@Test("SwiftSlashProcessGroup :: an .own nested launch survives its parent's group signal",
			.timeLimit(.minutes(1))
		)
		func ownPlacementNestedLaunchSurvivesParentGroupSignal() async throws {
			let run = try await startSpawnerFixture(mode:"stay", depth:0, placement:"own")
			defer { cleanUp(run) }
			try #require(run.recordedPIDs.count == 1, "the fixture recorded \(run.recordedPIDs.count) pid levels, expected exactly one")
			let grandchildPID = run.recordedPIDs[0]

			let grandchildGroup = getpgid(grandchildPID)
			#expect(grandchildGroup == grandchildPID,
				"an .own child must lead its own group; pid \(grandchildPID) reported group \(grandchildGroup)")

			let didSettle = await cancelLaunch(run)
			#expect(didSettle, "the outer launch never settled after its group signal")
			let gone = await waitForExit(of:grandchildPID, within:.seconds(2))
			#expect(gone == false,
				"an .own grandchild must not be reachable by the outer launch's group signal, but pid \(grandchildPID) is gone")
		}

		// MARK: - detachment

		/// a detached child outlives its launch on purpose, and is unreachable
		/// by design: it leads its own group and its own session.
		@Test("SwiftSlashProcessGroup :: a .detached child survives its launch and leads its own session",
			.timeLimit(.minutes(1))
		)
		func detachedChildSurvivesItsLaunch() async throws {
			let run = try await startSpawnerFixture(mode:"exit", depth:0, placement:"detached")
			defer { cleanUp(run) }
			try #require(run.recordedPIDs.count == 1, "the fixture recorded \(run.recordedPIDs.count) pid levels, expected exactly one")
			let detachedPID = run.recordedPIDs[0]

			// the fixture exits as soon as its child is published, so the launch
			// returns on its own rather than through a cancellation.
			let didSettle = await settled(run.launchTask, within:10.0)
			#expect(didSettle, "the launch never returned after its detached child was spawned")
			#expect(pidIsGone(run.outerPID), "the fixture should have exited")

			// the detached child is still running, and leads its own group and
			// session. this is what makes it unreachable rather than merely
			// un-signalled.
			#expect(kill(detachedPID, 0) == 0, "the .detached child did not survive its launch")
			#expect(getpgid(detachedPID) == detachedPID,
				"a .detached child must lead its own group; pid \(detachedPID) reported group \(getpgid(detachedPID))")
			#expect(getsid(detachedPID) == detachedPID,
				"a .detached child must lead its own session; pid \(detachedPID) reported session \(getsid(detachedPID))")

			// and the launch's group is gone entirely, so a group signal aimed
			// at the (now exited) launch cannot be delivered to anything. the
			// group is probed with signal 0 rather than actually signalled: the
			// pid could in principle have been recycled, and this test must not
			// be able to signal an unrelated group.
			#expect(kill(-run.outerPID, 0) == -1 && __cswiftslash_get_errno() == ESRCH,
				"a process group still exists at the launch's pid, so a group signal could still reach something")
			#expect(kill(detachedPID, 0) == 0, "the .detached child did not survive its launch's group being aimed at")
		}

		/// a detached node is the root of a fresh cascade: the children IT
		/// spawns join ITS group, not the group of the launch that created it.
		@Test("SwiftSlashProcessGroup :: a .detached node is the root of a fresh cascade",
			.timeLimit(.minutes(1))
		)
		func detachedNodeRootsAFreshCascade() async throws {
			// level 1 is asked to place its child detached, and that child is
			// told to place ITS child inherited — so the leaf joins the
			// detached process's group rather than the outer launch's.
			let run = try await startSpawnerFixture(mode:"stay", depth:1, placement:"detached", childPlacement:"inherited")
			defer { cleanUp(run) }
			try #require(run.recordedPIDs.count == 2, "the fixture recorded \(run.recordedPIDs.count) pid levels, expected two")

			// each level appends its own child's pid, and two processes race to append:
			// a level that has already published its child can be overtaken by the line
			// its own parent is about to write. so the pid at index 0 is NOT reliably
			// the outer one. identify the two by their relationship instead of by
			// their order in the file.
			let detachedPID = try #require(
				run.recordedPIDs.first { getpgid($0) == $0 && getsid($0) == $0 },
				"neither recorded pid leads its own group and session: \(run.recordedPIDs.map { "pid \($0) pgid \(getpgid($0)) sid \(getsid($0))" })"
			)
			let grandchildPID = try #require(
				run.recordedPIDs.first { $0 != detachedPID },
				"expected a second recorded pid"
			)

			#expect(getpgid(detachedPID) == detachedPID,
				"the detached node must lead its own group; pid \(detachedPID) reported group \(getpgid(detachedPID))")
			#expect(getsid(detachedPID) == detachedPID,
				"the detached node must lead its own session; pid \(detachedPID) reported session \(getsid(detachedPID))")
			#expect(getpgid(grandchildPID) == detachedPID,
				"an inherited child of a detached node must join the detached node's group; pid \(grandchildPID) reported group \(getpgid(grandchildPID)), expected \(detachedPID)")

			// the outer cascade cannot reach any of it.
			let didSettle = await cancelLaunch(run)
			#expect(didSettle, "the outer launch never settled after its group signal")
			let grandchildGone = await waitForExit(of:grandchildPID, within:.seconds(2))
			#expect(grandchildGone == false, "a detached subtree must not be reachable by the outer launch's group signal")
			#expect(kill(detachedPID, 0) == 0, "the detached node must survive the outer cascade")
		}

		// MARK: - signal recipients

		/// the public signal API can address the child's tree, not only its pid.
		/// a shell that forks a background job is the case that separates the
		/// two: the job inherits the shell's group, so a group-scoped signal
		/// reaches it and a pid-scoped one does not.
		@Test("SwiftSlashProcessGroup :: signal(to:.processGroup) reaches the child's whole tree",
			.timeLimit(.minutes(1))
		)
		func signalProcessGroupReachesTheTree() async throws {
			let markerPath = uniqueMarkerPath()
			defer { try? FileManager.default.removeItem(atPath:markerPath) }
			let script = "sleep 30 & echo $! > '\(markerPath)'; wait"
			let (process, runTask, shellPID) = try await launchShell(script)
			defer { _ = kill(shellPID, SIGKILL) }
			let innerPIDs = await markerPIDs(markerPath, expecting:1)
			try #require(innerPIDs.count == 1, "the shell never recorded its background child")
			let sleeperPID = innerPIDs[0]
			defer { _ = kill(sleeperPID, SIGKILL) }

			// the background job must share the shell's group, otherwise this
			// test would be measuring something other than recipient scope.
			#expect(getpgid(sleeperPID) == shellPID,
				"the background job was placed in group \(getpgid(sleeperPID)), expected the shell's group \(shellPID)")

			try await process.signal(SIGKILL, to:.processGroup)
			let sleeperGone = await waitForExit(of:sleeperPID, within:.seconds(5))
			#expect(sleeperGone, "a group-scoped signal must reach the child's background descendant")
			let didSettle = await settled(runTask, within:10.0)
			#expect(didSettle, "the launch never settled after its group signal")
		}

		/// the counterpart: `to:.process` addresses the direct child alone, so
		/// the recipient choice is observable rather than merely documented.
		@Test("SwiftSlashProcessGroup :: signal(to:.process) addresses the direct child alone",
			.timeLimit(.minutes(1))
		)
		func signalProcessAddressesTheChildAlone() async throws {
			let markerPath = uniqueMarkerPath()
			defer { try? FileManager.default.removeItem(atPath:markerPath) }
			let script = "sleep 30 & echo $! > '\(markerPath)'; wait"
			let (process, runTask, shellPID) = try await launchShell(script)
			defer { _ = kill(shellPID, SIGKILL) }
			let innerPIDs = await markerPIDs(markerPath, expecting:1)
			try #require(innerPIDs.count == 1, "the shell never recorded its background child")
			let sleeperPID = innerPIDs[0]
			defer { _ = kill(sleeperPID, SIGKILL) }

			try await process.signal(SIGKILL, to:.process)
			let sleeperGone = await waitForExit(of:sleeperPID, within:.seconds(2))
			#expect(sleeperGone == false,
				"a pid-scoped signal must leave the child's descendants alone, but pid \(sleeperPID) is gone")

			// release the survivor before waiting on the launch, whose io loops
			// the survivor is holding open.
			_ = kill(sleeperPID, SIGKILL)
			let didSettle = await settled(runTask, within:10.0)
			#expect(didSettle, "the launch never settled after its child was signalled")
		}

		// MARK: - reaping

		/// the reaping probe.
		///
		/// asserted per-pid rather than with `waitpid(-1)`: the wildcard form
		/// would reap a child the launch's own reaper is about to collect, which
		/// turns the probe into an interference. `ECHILD` here means the pid has
		/// been reaped by the launch and can never be waited for again — a
		/// stronger statement than the pid merely being gone.
		private func expectReapedByLaunch(_ pid:pid_t, _ label:String) {
			var status:Int32 = 0
			let reapResult = waitpid(pid, &status, WNOHANG)
			let reapErrno = __cswiftslash_get_errno()
			#expect(reapResult == -1 && reapErrno == ECHILD,
				"\(label): pid \(pid) was not reaped by the launch (waitpid returned \(reapResult), errno \(reapErrno))")
		}

		/// runs a command to completion, returning the pid it was given and the
		/// exit it produced. the pid is captured while the process is running,
		/// because it is not recoverable once the launch has reaped the child.
		private func runToCompletion(_ command:Command, placement:ChildProcess.ProcessGroup = .own) async throws -> (pid:pid_t, exit:ChildProcess.Exit) {
			let process = ChildProcess(command, processGroup:placement)
			let runTask = Task { () -> ChildProcess.Exit in
				try await process.run()
			}
			let running = await waitUntilRunning(process)
			guard case .running(let pid) = running else {
				runTask.cancel()
				throw FixtureError.launchNeverRan
			}
			let exit = try await runTask.value
			return (pid, exit)
		}

		/// cancels a launch and returns the pid it was given. the run is
		/// expected to surface `CancellationError`.
		private func cancelAndReap(_ command:Command, placement:ChildProcess.ProcessGroup = .own) async throws -> pid_t {
			let process = ChildProcess(command, processGroup:placement)
			let runTask = Task { () -> ChildProcess.Exit in
				try await process.run(cancellationSignal:ChildProcess.defaultCancellationSignal)
			}
			let running = await waitUntilRunning(process)
			guard case .running(let pid) = running else {
				runTask.cancel()
				throw FixtureError.launchNeverRan
			}
			runTask.cancel()
			do {
				_ = try await runTask.value
				Issue.record("expected CancellationError, but the run produced a result")
			} catch is CancellationError {
				// expected
			}
			return pid
		}

		@Test("SwiftSlashProcessGroup :: a normal exit is reaped",
			.timeLimit(.minutes(1))
		)
		func normalExitIsReaped() async throws {
			// the child lingers briefly so its pid is observable before it
			// exits. a child that exits immediately can be reaped before the
			// launch's state can be read, and this test needs the pid in order
			// to prove WHICH process the launch reaped.
			let (pid, exit) = try await runToCompletion(Command(absolutePath:"/bin/sh", arguments:["-c", "sleep 0.3; exit 0"]))
			#expect(exit == .code(0), "expected a clean exit, got \(exit)")
			expectReapedByLaunch(pid, "normal exit")
		}

		@Test("SwiftSlashProcessGroup :: a non-zero exit is reaped",
			.timeLimit(.minutes(1))
		)
		func nonZeroExitIsReaped() async throws {
			// lingering for the same reason as the normal-exit case above.
			let (pid, exit) = try await runToCompletion(Command(absolutePath:"/bin/sh", arguments:["-c", "sleep 0.3; exit 3"]))
			#expect(exit == .code(3), "expected exit 3, got \(exit)")
			expectReapedByLaunch(pid, "non-zero exit")
		}

		/// a launch that fails before the spawn creates no child at all, so
		/// there is nothing to reap — and, crucially, it fails rather than
		/// parking forever on a continuation nothing will resume.
		@Test("SwiftSlashProcessGroup :: a launch that cannot spawn throws instead of parking",
			.timeLimit(.minutes(1))
		)
		func unrunnablePathThrows() async throws {
			let process = ChildProcess(Command(absolutePath:"/nonexistent-swiftslash-fixture/binary"))
			let runTask = Task { () -> ChildProcess.Exit in
				try await process.run()
			}
			let settled = await self.settled(runTask, within:10.0)
			#expect(settled, "a launch against an unrunnable path never settled: it is parked on a continuation nothing will resume")
			let outcome = await runTask.result
			switch outcome {
				case .success(let exit):
					Issue.record("expected the launch to throw, but it exited with \(exit)")
				case .failure(let error):
					#expect(error is ChildProcess.SpawnError,
						"expected a spawn error, got \(type(of:error)): \(error)")
			}
		}

		@Test("SwiftSlashProcessGroup :: a cancelled run is reaped (.own)",
			.timeLimit(.minutes(1))
		)
		func cancelledOwnRunIsReaped() async throws {
			let pid = try await cancelAndReap(Command(absolutePath:"/bin/sleep", arguments:["30"]))
			expectReapedByLaunch(pid, "cancelled .own run")
		}

		/// an `.inherited` child is in THIS process's group, so its teardown
		/// must address the child's pid alone. if the teardown signalled the
		/// group instead, it would signal this very test runner — the test
		/// completing at all is part of the evidence, and it is why the
		/// placement-dependent teardown target exists.
		@Test("SwiftSlashProcessGroup :: a cancelled run is reaped (.inherited) without signalling the caller's group",
			.timeLimit(.minutes(1))
		)
		func cancelledInheritedRunIsReaped() async throws {
			let pid = try await cancelAndReap(Command(absolutePath:"/bin/sleep", arguments:["30"]), placement:.inherited)
			expectReapedByLaunch(pid, "cancelled .inherited run")
			#expect(getpgid(0) == getpid(), "the test runner's own group was disturbed")
		}

		/// placement decides reachability, not whether the launch cleans up
		/// after itself: a cancelled `.detached` launch still signals and reaps
		/// the child it created. what it does not do is reach anything else.
		@Test("SwiftSlashProcessGroup :: a cancelled run is reaped (.detached)",
			.timeLimit(.minutes(1))
		)
		func cancelledDetachedRunIsReaped() async throws {
			let pid = try await cancelAndReap(Command(absolutePath:"/bin/sleep", arguments:["30"]), placement:.detached)
			expectReapedByLaunch(pid, "cancelled .detached run")
		}

		/// a child that ignores the cancellation signal is not reaped by the
		/// cancellation, and the launch does not escalate — the caller's
		/// documented recourse is to send SIGKILL. once the child does die, the
		/// launch must still reap it.
		@Test("SwiftSlashProcessGroup :: a child that ignores the cancellation signal is still reaped on escalation",
			.timeLimit(.minutes(1))
		)
		func ignoresCancellationThenEscalationIsReaped() async throws {
			let process = ChildProcess(Command(absolutePath:"/bin/sh", arguments:["-c", "trap '' TERM; while :; do sleep 1; done"]))
			let runTask = Task { () -> ChildProcess.Exit in
				try await process.run(cancellationSignal:ChildProcess.defaultCancellationSignal)
			}
			let running = await waitUntilRunning(process)
			guard case .running(let pid) = running else {
				runTask.cancel()
				throw FixtureError.launchNeverRan
			}
			runTask.cancel()
			// the child ignores SIGTERM, so it is deliberately still alive here.
			try? await Task.sleep(for:.milliseconds(300))
			#expect(kill(pid, 0) == 0, "the child was expected to ignore SIGTERM but it is gone")

			// escalate: one signal, once, chosen by the caller.
			try await process.signal(SIGKILL, to:.processGroup)
			do {
				_ = try await runTask.value
				Issue.record("expected CancellationError, but the run produced a result")
			} catch is CancellationError {
				// expected
			}
			expectReapedByLaunch(pid, "ignores-cancellation")
		}
		// MARK: - automatic placement (the reserved descriptor)

		/// the descriptor numbers open in this process, across the caller's range.
		/// probed through the C helper because glibc's `fcntl` is variadic and swift
		/// refuses to call it on linux.
		private func openDescriptors(from lowest:Int32 = 3, through highest:Int32 = 255) -> [Int32] {
			var open:[Int32] = []
			for candidate in lowest...highest {
				if __cswiftslash_fcntl_getfd(candidate) != -1 {
					open.append(candidate)
				}
			}
			return open
		}

		/// reads a one-line report the fixture wrote, bounded.
		private func readReport(_ path:String) async -> String {
			for _ in 0..<400 {
				if let contents = try? String(contentsOfFile:path, encoding:.utf8) {
					return contents.trimmingCharacters(in:.whitespacesAndNewlines)
				}
				try? await Task.sleep(for:.milliseconds(25))
			}
			return ""
		}

		// MARK: - automatic placement

		/// the payoff for the descriptor: the same shape as the escape this release
		/// closes, but the nested launch is told NOTHING and works it out from the
		/// process relationship it is already in.
		@Test("SwiftSlashProcessGroup :: a nested launch cascades without being told how",
			.timeLimit(.minutes(1))
		)
		func automaticPlacementCascadesWithoutInstruction() async throws {
			let run = try await startSpawnerFixture(mode:"stay", depth:0)
			defer { cleanUp(run) }
			try #require(run.recordedPIDs.count == 1, "the fixture recorded \(run.recordedPIDs.count) pid levels, expected exactly one")
			let nestedPID = run.recordedPIDs[0]

			// pin the MECHANISM: the nested launch has to be in the fixture's group
			// before any signal is sent. nothing was passed on the command line, so
			// only the descriptor could have decided this.
			let nestedGroup = getpgid(nestedPID)
			#expect(nestedGroup == run.outerPID,
				"the nested launch was placed in group \(nestedGroup); automatic placement should have joined the fixture group \(run.outerPID)")

			let didSettle = await cancelLaunch(run)
			try #require(didSettle, "the outer launch never settled after its group signal")
			let gone = await waitForExit(of:nestedPID, within:.seconds(5))
			#expect(gone, "a nested launch that was never told how to place itself survived its parent group signal")
		}

		/// cascading has to survive more than one level, or the fix only moves the
		/// escape one generation deeper. every level here decides for itself.
		@Test("SwiftSlashProcessGroup :: automatic placement is transitive through nested generations",
			.timeLimit(.minutes(1))
		)
		func automaticPlacementIsTransitive() async throws {
			let run = try await startSpawnerFixture(mode:"stay", depth:1)
			defer { cleanUp(run) }
			try #require(run.recordedPIDs.count == 2, "the fixture recorded \(run.recordedPIDs.count) pid levels, expected two")
			// which of the two is which does not matter here: this test asserts on
			// where BOTH sit, so it is immune to the append race the helper documents.
			let middlePID = run.recordedPIDs[0]
			let leafPID = run.recordedPIDs[1]

			// one group for all three generations: the fixture, the generation it
			// spawned, and the leaf that generation spawned.
			#expect(getpgid(middlePID) == run.outerPID,
				"the middle generation is in group \(getpgid(middlePID)), expected \(run.outerPID)")
			#expect(getpgid(leafPID) == run.outerPID,
				"the leaf is in group \(getpgid(leafPID)), expected \(run.outerPID)")

			let didSettle = await cancelLaunch(run)
			try #require(didSettle, "the outer launch never settled after its group signal")
			let middleGone = await waitForExit(of:middlePID, within:.seconds(5))
			let leafGone = await waitForExit(of:leafPID, within:.seconds(5))
			#expect(middleGone, "the middle generation survived the outermost group signal")
			#expect(leafGone, "the leaf survived the outermost group signal: the cascade stops one level down")
		}

		/// what happens when a program reuses the reserved number for its own
		/// purposes. the probe finds no record, the launch falls back to the
		/// historical placement, and nothing crashes.
		@Test("SwiftSlashProcessGroup :: a reused reserved descriptor degrades to the historical placement",
			.timeLimit(.minutes(1))
		)
		func reusedReservedDescriptorDegradesGracefully() async throws {
			let run = try await startSpawnerFixture(mode:"stay", depth:0, closeFD3:true)
			defer { cleanUp(run) }
			try #require(run.recordedPIDs.count == 1, "the fixture recorded \(run.recordedPIDs.count) pid levels, expected exactly one")
			let nestedPID = run.recordedPIDs[0]

			// with no descriptor to read, the launch has nothing to cascade from, so
			// the nested child leads its own group. this is the documented
			// degradation, not a failure: the alternative is a crash or a guess.
			#expect(getpgid(nestedPID) == nestedPID,
				"a launch with no descriptor must fall back to leading its own group; pid \(nestedPID) reported group \(getpgid(nestedPID))")

			let didSettle = await cancelLaunch(run)
			try #require(didSettle, "the outer launch never settled after its group signal")
			let gone = await waitForExit(of:nestedPID, within:.seconds(2))
			#expect(gone == false, "the degraded placement is the historical one, which survives a parent group signal")
		}

		// MARK: - descriptor lifetime and verification

		/// the descriptor belongs to the launch, not to the caller: a launch that
		/// held one for its lifetime would grow the caller's descriptor table once
		/// per launch.
		@Test("SwiftSlashProcessGroup :: a launch leaves no descriptor behind in the caller",
			.timeLimit(.minutes(2))
		)
		func launchDescriptorsDoNotLeakIntoTheCaller() async throws {
			// the suite is serialized, but swift testing still runs OTHER suites in
			// this process concurrently and the descriptor table is process-wide, so a
			// single before/after pair can be perturbed by a neighbouring suite. the
			// measurement is therefore retried: a neighbouring suite's descriptors are
			// transient, a leaked one is not.
			var appeared:[Int32] = []
			for _ in 0..<3 {
				let before = Set(openDescriptors())
				for _ in 0..<8 {
					let process = ChildProcess(Command(absolutePath:"/bin/echo", arguments:["descriptor-hygiene"]))
					_ = try await process.run()
				}
				appeared = openDescriptors().filter { before.contains($0) == false }
				if appeared.isEmpty {
					return
				}
			}
			Issue.record("a launch left \(appeared.count) descriptor(s) open in the caller: \(appeared)")
		}

		/// the record's magic is not enough to be believed: it has to agree with
		/// where the process actually sits, or a process holding a stale descriptor
		/// at the reserved number would inherit a placement nobody gave it.
		///
		/// the check runs inside the FIXTURE's own process. the reserved number is
		/// process-wide state, so driving it from here would mutate something every
		/// other concurrently-running suite shares; a short-lived fixture replacing
		/// its own descriptor harms nobody.
		@Test("SwiftSlashProcessGroup :: the reserved descriptor is verified, not merely recognised",
			.timeLimit(.minutes(1))
		)
		func reservedDescriptorIsVerified() async throws {
			guard Self.spawnerPath.isEmpty == false else {
				throw FixtureError.spawnerBinaryMissing([#filePath])
			}
			let reportPath = uniqueMarkerPath()
			defer { try? FileManager.default.removeItem(atPath:reportPath) }

			let process = ChildProcess(Command(
				absolutePath:Path(Self.spawnerPath),
				arguments:["--verify-descriptor=\(reportPath)"],
				environment:CurrentEnvironment.environmentVariables()
			))
			let exit = try await process.run()
			#expect(exit == .code(0), "the verification run exited \(exit)")

			let report = await readReport(reportPath)
			try #require(report.isEmpty == false, "the fixture produced no verification report")
			let results = report.split(separator:" ").compactMap { Int32($0) }
			try #require(results.count == 2, "unexpected verification report: \(report)")

			// a record naming a group this process is not in must be refused.
			#expect(results[0] != 0,
				"a record claiming a group the process is not in was accepted as its enclosing launch")
			// and the same shape agreeing with the process's real group must be
			// accepted, or a probe that simply rejected everything would pass.
			#expect(results[1] == 0,
				"a record that agrees with the process actual group was rejected")
		}
		/// a program that reuses the reserved number for a channel of its own must not
		/// be able to hang the launch merely by holding it open. this is the case a
		/// closed-descriptor test cannot see: an OPEN descriptor with a live writer
		/// never reports end-of-file, so a bare read on it waits for a write that
		/// will never come.
		@Test("SwiftSlashProcessGroup :: an open reserved descriptor does not hang the launch",
			.timeLimit(.minutes(1))
		)
		func openReservedDescriptorDoesNotHang() async throws {
			// the fixture publishes its child's pid only after its own launch has
			// completed, so reaching this line at all is the anti-hang assertion.
			let run = try await startSpawnerFixture(mode:"stay", depth:0, blockingFD3:true)
			defer { cleanUp(run) }
			try #require(run.recordedPIDs.count == 1, "the fixture recorded \(run.recordedPIDs.count) pid levels, expected exactly one")
			let nestedPID = run.recordedPIDs[0]

			// nothing readable at the reserved number means no enclosing launch, so
			// the launch falls back to the historical placement.
			#expect(getpgid(nestedPID) == nestedPID,
				"a launch whose descriptor holds nothing readable must fall back to leading its own group; pid \(nestedPID) reported group \(getpgid(nestedPID))")

			let didSettle = await cancelLaunch(run)
			try #require(didSettle, "the outer launch never settled after its group signal")
			_ = await waitForExit(of:nestedPID, within:.seconds(2))
		}

		/// the public surface for the same knowledge.
		@Test("SwiftSlashProcessGroup :: a launched process can see the launch it is inside",
			.timeLimit(.minutes(1))
		)
		func launchIdentityIsAvailableInsideALaunch() async throws {
			// outside any launch there is nothing to report, and the probe has to say
			// so rather than latching onto whatever the runner holds at that number.
			#expect(CurrentEnvironment.launchIdentity() == nil,
				"this process is not the child of a launch, so it must report no enclosing launch")

			let run = try await startSpawnerFixture(mode:"stay", depth:0, identityReport:true)
			defer { cleanUp(run) }
			try #require(run.identityPath.isEmpty == false, "the fixture was not asked to report an identity")
			let report = await readReport(run.identityPath)
			try #require(report.isEmpty == false, "the fixture never reported its launch identity")
			let fields = report.split(separator:" ")
			try #require(fields.count == 3, "unexpected identity report: \(report)")

			// the fixture was launched by THIS process, and the launch gave it its own
			// group, so the reported placement is both proof that the launcher is
			// known and a cross-check of the documented default.
			#expect(Int32(fields[0]) == getpid(),
				"the fixture reported launcher pid \(fields[0]), expected this process (\(getpid()))")
			#expect(Int32(fields[1]) == run.outerPID,
				"the fixture reported group \(fields[1]); a defaulted launch gives its child its own group (\(run.outerPID))")
			#expect(Int32(fields[2]) == getsid(0),
				"the fixture reported session \(fields[2]), expected the launcher session (\(getsid(0)))")
		}
	}
}