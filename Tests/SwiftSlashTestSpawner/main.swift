/*
LICENSE MIT
copyright (c) tanner silva 2026. all rights reserved.

   _____      ______________________   ___   ______ __
  / __/ | /| / /  _/ __/_  __/ __/ /  / _ | / __/ // /
 _\ \ | |/ |/ // // _/  / / _\ \/ /__/ __ |_\ \/ _  /
/___/ |__/|__/___/_/   /_/ /___/____/_/ |_/___/_//_/

*/

// a test fixture process that spawns its own child *through swiftslash*.
//
// this is the shape that produced arc's orphan: a swift process (a "plugin
// host") that itself uses swiftslash to launch a tool. the fixture exists so
// the process-group suite can assert what happens to that nested child when an
// outer launch's group signal arrives.
//
// deliberately foundation-free: these tests measure the process's fd table and
// its group/session placement, so the fixture must not carry the startup
// footprint of a larger runtime.
//
// it accepts flags rather than positionals so a later phase can add an option
// without disturbing an earlier phase's call sites:
//
//   --self=<path>        this fixture's own absolute path, for recursion
//   --mode=stay|exit     stay alive after spawning, or exit once it is spawned
//   --marker=<path>      append the direct child's pid here, one line per level
//   --depth=<n>          spawner generations below this one before the leaf
//   --placement=<mode>   placement for the direct child (see the suite)
//   --close-fd3          close the reserved descriptor before spawning
//   --identity=<path>    write what this process knows about its enclosing launch
//   --verify-descriptor=<path>   verify the reserved descriptor in this process, then exit
//   --blocking-fd3       hold an OPEN, EMPTY pipe at the reserved descriptor
//
// everything lives inside a type rather than at the top level: a top-level
// `var` in main.swift is main-actor isolated, so a nonisolated helper could not
// read it.

import SwiftSlash
import __cswiftslash_posix_helpers
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// the parsed command line. absent options are simply absent; `--placement` in
/// particular means "say nothing and let the launch decide", which is the case
/// the automatic resolution in a later phase is measured against.
private struct Configuration:Sendable {
	let selfPath:String
	let mode:String
	let markerPath:String
	let depth:Int
	let requestedPlacement:String?
	/// the placement a nested generation should request for ITS direct child.
	/// absent means "propagate this level's request", which is what a chain of
	/// identically-placed launches wants.
	let childPlacement:String?
	let closeReservedDescriptor:Bool
	/// hold an open, empty pipe at the reserved number before spawning: a
	/// descriptor with a live writer that reports no end-of-file.
	let bindBlockingReservedDescriptor:Bool
	/// where to write ``CurrentEnvironment/launchIdentity()``, or nil to not report it.
	let identityPath:String?

	/// the placement to request for the direct child. only meaningful when the
	/// caller actually named one: an absent `--placement` means "say nothing and
	/// let the launch decide", which is the case the automatic resolution is
	/// measured against.
	var placement:ChildProcess.ProcessGroup {
		switch requestedPlacement {
			case "inherited":
				return .inherited
			case "detached":
				return .detached
			default:
				return .own
		}
	}

	static func parse(_ arguments:[String]) -> Configuration? {
		var values:[String:String] = [:]
		var flags:Set<String> = []
		for argument in arguments.dropFirst() {
			guard argument.hasPrefix("--") else {
				continue
			}
			let body = argument.dropFirst(2)
			if let separator = body.firstIndex(of: "=") {
				values[String(body[body.startIndex..<separator])] = String(body[body.index(after:separator)...])
			} else {
				flags.insert(String(body))
			}
		}
		guard let selfPath = values["self"],
			let mode = values["mode"],
			let markerPath = values["marker"],
			let depthText = values["depth"],
			let depth = Int(depthText)
		else {
			return nil
		}
		return Configuration(
			selfPath:selfPath,
			mode:mode,
			markerPath:markerPath,
			depth:depth,
			requestedPlacement:values["placement"],
			childPlacement:values["child-placement"],
			closeReservedDescriptor:flags.contains("close-fd3"),
			bindBlockingReservedDescriptor:flags.contains("blocking-fd3"),
			identityPath:values["identity"]
		)
	}
}

private enum SpawnerFixture {
	/// the leaf process every chain eventually spawns.
	static let leafExecutable = "/bin/sleep"
	/// long enough that no assertion in the suite can race a natural exit.
	static let leafSeconds = "30"

	/// build the command for this level's direct child: either another spawner
	/// generation, or the leaf.
	static func childCommand(_ config:Configuration) -> Command {
		// the environment is passed down the chain explicitly: a nested
		// generation is a swift binary and needs the runtime's own library
		// lookup paths, and a launch's default environment is deliberately
		// empty.
		let environment = CurrentEnvironment.environmentVariables()
		guard config.depth > 0 else {
			return Command(absolutePath:Path(leafExecutable), arguments:[leafSeconds], environment:environment)
		}
		var childArguments = [
			"--self=\(config.selfPath)",
			"--mode=\(config.mode)",
			"--marker=\(config.markerPath)",
			"--depth=\(config.depth - 1)",
		]
		// the placement the nested generation should request for its own direct
		// child. absent means this level's request is propagated down the chain.
		if let nestedPlacement = config.childPlacement ?? config.requestedPlacement {
			childArguments.append("--placement=\(nestedPlacement)")
		}
		if config.closeReservedDescriptor {
			childArguments.append("--close-fd3")
		}
		return Command(absolutePath:Path(config.selfPath), arguments:childArguments, environment:environment)
	}

	/// verify the reserved descriptor in THIS process and report what the probe
	/// said. it runs here rather than in the test process because the reserved
	/// number is process-wide state: a test that replaced it would be mutating
	/// something every other concurrently-running suite shares.
	///
	/// writes "<forged> <valid>", where each value is the probe's return code
	/// (0 = accepted). never returns.
	static func reportReservedDescriptorVerification(_ reportPath:String) -> Never {
		// a record with the right magic and version, claiming an .inherited
		// placement in a group this process is not in.
		var forged = __cswiftslash_launch_descriptor()
		forged.magic = 0x53575F534C415348
		forged.version = 1
		forged.placement = Int32(__cswiftslash_pgroup_mode_inherited.rawValue)
		forged.launcher_pid = getpid()
		forged.launcher_pgid = getpgid(0) == 1 ? 2 : 1

		// the positive control: the same shape, agreeing with where this process
		// actually sits. without it, a probe that rejected everything would look
		// indistinguishable from a probe that verifies.
		var valid = __cswiftslash_launch_descriptor()
		valid.magic = 0x53575F534C415348
		valid.version = 1
		valid.placement = Int32(__cswiftslash_pgroup_mode_inherited.rawValue)
		valid.launcher_pid = getpid()
		valid.launcher_pgid = getpgid(0)

		let savedReservedFD = dup(3)
		let forgedResult = probeInstalledRecord(forged)
		let validResult = probeInstalledRecord(valid)
		if savedReservedFD >= 0 {
			_ = dup2(savedReservedFD, 3)
			_ = close(savedReservedFD)
		} else {
			_ = close(3)
		}

		guard let handle = fopen(reportPath, "w") else {
			exit(71)
		}
		fputs("\(forgedResult) \(validResult)\n", handle)
		fclose(handle)
		exit(0)
	}

	/// installs `record` at the reserved number and returns the probe's verdict.
	/// -99 and -98 report a failure to set the check up at all, so a broken
	/// fixture cannot read as a probe result.
	static func probeInstalledRecord(_ record:__cswiftslash_launch_descriptor) -> Int32 {
		var payload = record
		var readFD:Int32 = -1
		var writeFD:Int32 = -1
		guard __cswiftslash_create_launch_descriptor(&readFD, &writeFD) == 0 else {
			return -99
		}
		let written = withUnsafeBytes(of:&payload) { buffer -> Int in
			return write(writeFD, buffer.baseAddress, buffer.count)
		}
		_ = close(writeFD)
		guard written == MemoryLayout<__cswiftslash_launch_descriptor>.size, dup2(readFD, 3) >= 0 else {
			_ = close(readFD)
			return -98
		}
		_ = close(readFD)
		var probed = __cswiftslash_launch_descriptor()
		return Int32(__cswiftslash_probe_launch_descriptor(&probed))
	}

	/// the report path a verification run was asked for, or nil for a normal run.
	static func verificationReportPath(_ arguments:[String]) -> String? {
		for argument in arguments.dropFirst() where argument.hasPrefix("--verify-descriptor=") {
			return String(argument.dropFirst("--verify-descriptor=".count))
		}
		return nil
	}

	/// write what this process knows about its enclosing launch. `none` is written
	/// when there is no enclosing launch, which is equally worth asserting.
	static func recordIdentity(_ config:Configuration) {
		guard let identityPath = config.identityPath, let handle = fopen(identityPath, "w") else {
			return
		}
		if let identity = CurrentEnvironment.launchIdentity() {
			fputs("\(identity.launcherPID) \(identity.processGroup) \(identity.session)\n", handle)
		} else {
			fputs("none\n", handle)
		}
		fclose(handle)
	}

	/// append a pid to the marker file. the marker is opened for append so every
	/// level's line is atomic and the suite can read the whole chain.
	static func recordChildPID(_ config:Configuration, pid:pid_t) {
		guard let handle = fopen(config.markerPath, "a") else {
			return
		}
		fputs("\(pid)\n", handle)
		fclose(handle)
	}

	static func run() async {
		// a verification run is standalone: it inspects the reserved descriptor in
		// its own process and needs none of the spawner's options.
		if let reportPath = verificationReportPath(CommandLine.arguments) {
			reportReservedDescriptorVerification(reportPath)
		}
		guard let config = Configuration.parse(CommandLine.arguments) else {
			// no stdio: on linux `stderr` imports as a mutable global and
			// referencing it is a swift 6 concurrency error. the exit code is
			// the whole signal.
			exit(64)
		}

		// a fixture that closes the reserved descriptor is simulating a program
		// that reuses fd 3 for its own purposes. the launch must degrade
		// gracefully rather than crash.
		if config.closeReservedDescriptor {
			_ = close(3)
		}

		// a fixture that leaves an open, empty pipe at the reserved number is
		// simulating a program that reused descriptor 3 for a channel of its own.
		// the write end stays open on purpose: it is what makes the descriptor
		// readable-only-after-someone-writes, so a bare read on it would wait
		// forever rather than report end-of-file.
		if config.bindBlockingReservedDescriptor {
			var pipeEnds:[Int32] = [-1, -1]
			if pipe(&pipeEnds) == 0 {
				_ = dup2(pipeEnds[0], 3)
				_ = close(pipeEnds[0])
			}
		}

		// report the enclosing launch BEFORE the spawn: the probe consumes the record,
		// and this is the answer the launch resolution will also use.
		recordIdentity(config)

		// only request a placement when the caller named one. a launch that is told
		// nothing decides for itself.
		let child:ChildProcess
		if config.requestedPlacement != nil {
			child = ChildProcess(childCommand(config), processGroup:config.placement)
		} else {
			child = ChildProcess(childCommand(config))
		}

		// the launch is owned by this task for the life of the process: `run()`
		// is what performs the spawn and drives the io loops, and the fixture
		// deliberately does not await it so the process can outlive the
		// assertion window.
		_ = Task {
			try? await child.run()
		}

		// the pid is published through the actor's state, so poll for it rather
		// than guessing when posix_spawn has completed.
		var directChildPID:pid_t = 0
		for _ in 0..<600 {
			if case .running(let pid) = await child.state {
				directChildPID = pid
				break
			}
			try? await Task.sleep(for:.milliseconds(5))
		}
		guard directChildPID > 0 else {
			// the launch never produced a pid: there is nothing to assert about.
			exit(70)
		}
		recordChildPID(config, pid:directChildPID)

		switch config.mode {
			case "exit":
				// the child is launched and published, and this process is now
				// free to go: anything it spawned keeps running and is
				// reparented. the brief linger exists so that the parent can
				// observe the running state (and therefore the pid it was
				// given) before this process disappears; it changes nothing
				// about the placement being tested.
				try? await Task.sleep(for:.milliseconds(300))
				exit(0)
			default:
				// stay alive so an outer launch's teardown has something to
				// signal, and so a group signal's effect on this process is
				// observable.
				try? await Task.sleep(for:.seconds(3600))
		}
	}
}

await SpawnerFixture.run()