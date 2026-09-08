import Testing
@testable import SwiftSlash
import __cswiftslash_posix_helpers
import SwiftSlashFHHelpers

extension Tag {
	@Tag internal static var byoDataChannelTests:Self
}

extension SwiftSlashTests {
	@Suite("BYODataChannelTests",
		.serialized,
		.tags(.byoDataChannelTests)
	)
	struct BYODataChannelTests {

		/// blocking read loop that collects every byte available on a descriptor until
		/// it observes EOF (a zero-length read). only returns when the descriptor sees
		/// EOF, so the caller must drop the last writer reference before awaiting this.
		private func readAllBytes(fd:Int32) -> [UInt8] {
			var collected:[UInt8] = []
			readLoop: while true {
				var buf = [UInt8](repeating:0, count:4096)
				guard let readCount = try? fd.readFH(into:&buf, size:buf.count), readCount > 0 else {
					break readLoop
				}
				collected.append(contentsOf:buf[0..<readCount])
			}
			return collected
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

		@Test("BYODataChannelTests :: stdout byo passthrough with no line splitting",
			.timeLimit(.minutes(1))
		)
		func testByoStdout() async throws {
			// fabricate a caller-owned pipe. swiftslash receives the writing end
			// (child-facing); the test keeps the reading end and consumes it raw.
			let pipe = try PosixPipe()
			defer {
				try? pipe.reading.closeFileHandle()
				try? pipe.writing.closeFileHandle()
			}
			// the child generates a payload far larger than any platform pipe capacity
			// (PIPE_BUF / pipe buffer), so a complete drain requires the caller's read
			// loop to consume concurrently while the child writes. byte-exact equality
			// proves swiftslash is not in the data path and does no chunking of its own.
			let marker = "byo-passthrough_\(Int.random(in:0...Int.max))_"
			let byteCount = 200_000
			let command = "yes '\(marker)' | head -c \(byteCount)"
			var expected:[UInt8] = []
			let unit = Array((marker + "\n").utf8)
			while expected.count < byteCount {
				expected.append(contentsOf:unit)
			}
			expected.removeLast(expected.count - byteCount)
			let process = ChildProcess(Command(absolutePath:"/bin/sh", arguments:["-c", command]), dataChannels:[
				STDOUT_FILENO: .write(.byo(fd:.init(rawValue:pipe.writing))),
				STDERR_FILENO: .write(.toNull),
				STDIN_FILENO: .read(.fromNull)
			])
			async let exitResult = process.run()
			let readerTask = Task { () -> [UInt8] in
				self.readAllBytes(fd:pipe.reading)
			}
			let exit = try await exitResult
			// swiftslash must not have closed the caller-owned descriptor. drop the
			// parent-side copy of the child-facing end so the retained end sees EOF.
			#expect(__cswiftslash_fcntl_getfd(pipe.writing) >= 0, "swiftslash must not close a caller-owned descriptor")
			try? pipe.writing.closeFileHandle()
			let bytes = await readerTask.result.get()
			#expect(exit == .code(0))
			#expect(bytes.count == byteCount, "expected exactly \(byteCount) raw bytes")
			#expect(bytes == expected, "expected the exact raw payload with no line splitting or mangling")
		}

		@Test("BYODataChannelTests :: stdin byo feeder observes EOF",
			.timeLimit(.minutes(1))
		)
		func testByoStdin() async throws {
			let pipe = try PosixPipe()
			defer {
				try? pipe.reading.closeFileHandle()
				try? pipe.writing.closeFileHandle()
			}
			let randomInt = Int.random(in:0...Int.max)
			let payload = "byo stdin payload \(randomInt)\n"
			let process = ChildProcess(Command(absolutePath:"/bin/cat"), dataChannels:[
				STDIN_FILENO: .read(.byo(fd:.init(rawValue:pipe.reading))),
				STDOUT_FILENO: .write(.toNull),
				STDERR_FILENO: .write(.toNull)
			])
			async let exitResult = process.run()
			// feed the payload through the caller-owned pipe, then drop the writing
			// end so the child observes EOF and can exit.
			let payloadBytes = Array(payload.utf8)
			_ = try payloadBytes.withUnsafeBufferPointer { writeBuffer in
				try pipe.writing.writeFH(writeBuffer)
			}
			try? pipe.writing.closeFileHandle()
			let exit = try await exitResult
			#expect(exit == .code(0), "cat should exit cleanly after reading the payload and observing EOF")
		}

		@Test("BYODataChannelTests :: mixed built-in stdout and byo stderr on one process",
			.timeLimit(.minutes(1))
		)
		func testByoMixed() async throws {
			let errPipe = try PosixPipe()
			defer {
				try? errPipe.reading.closeFileHandle()
				try? errPipe.writing.closeFileHandle()
			}
			let process = ChildProcess(Command(absolutePath:"/bin/sh", arguments:["-c", "echo mixed-out; echo mixed-err >&2"]), dataChannels:[
				STDOUT_FILENO: .write(.toParentProcess(stream:.init(), separator:[0x0A])),
				STDERR_FILENO: .write(.byo(fd:.init(rawValue:errPipe.writing))),
				STDIN_FILENO: .read(.fromNull)
			])
			async let exitResult = process.run()
			let outTask = Task { () -> [[UInt8]] in
				var lines:[[UInt8]] = []
				for await lineChunk in process.stdout {
					lines.append(contentsOf:lineChunk)
				}
				return lines
			}
			let errTask = Task { () -> [UInt8] in
				self.readAllBytes(fd:errPipe.reading)
			}
			let exit = try await exitResult
			// drop the parent-side copy of the child-facing descriptor so the
			// retained end observes EOF.
			try? errPipe.writing.closeFileHandle()
			let outLines = await outTask.result.get()
			let errBytes = await errTask.result.get()
			#expect(exit == .code(0))
			#expect(outLines.count == 1, "expected exactly one line of built-in stdout")
			#expect(String(bytes:outLines.first!, encoding:.utf8) == "mixed-out")
			#expect(String(bytes:errBytes, encoding:.utf8) == "mixed-err\n", "expected raw stderr bytes with no line splitting")
		}

		@Test("BYODataChannelTests :: swapped pipe end is rejected up front",
			.timeLimit(.minutes(1))
		)
		func testByoWrongDirection() async throws {
			let pipe = try PosixPipe()
			defer {
				try? pipe.reading.closeFileHandle()
				try? pipe.writing.closeFileHandle()
			}
			// a child-writing (stdout) channel cannot be fed a read-only descriptor:
			// the child would write into a reader end and fail in the child. this is
			// the classic swapped-end mistake and must be caught before spawn.
			let wrongWriter = ChildProcess(Command(absolutePath:"/bin/echo", arguments:["x"]), dataChannels:[
				STDOUT_FILENO: .write(.byo(fd:.init(rawValue:pipe.reading))),
				STDERR_FILENO: .write(.toNull),
				STDIN_FILENO: .read(.fromNull)
			])
			await #expect(throws:ChildProcess.SpawnError.byoFileDescriptorWrongDirection) {
				try await wrongWriter.run()
			}
			// and the mirror image: a child-reading (stdin) channel cannot be fed a
			// write-only descriptor.
			let wrongReader = ChildProcess(Command(absolutePath:"/bin/cat"), dataChannels:[
				STDIN_FILENO: .read(.byo(fd:.init(rawValue:pipe.writing))),
				STDOUT_FILENO: .write(.toNull),
				STDERR_FILENO: .write(.toNull)
			])
			await #expect(throws:ChildProcess.SpawnError.byoFileDescriptorWrongDirection) {
				try await wrongReader.run()
			}
		}

		@Test("BYODataChannelTests :: task cancellation with a sigterm-ignoring child stays actor-responsive and then reaps",
			.timeLimit(.minutes(1))
		)
		func testByoStubbornCancellation() async throws {
			let pipe = try PosixPipe()
			defer {
				try? pipe.reading.closeFileHandle()
				try? pipe.writing.closeFileHandle()
			}
			// the shell ignores SIGTERM and loops forever, so cancellation cannot
			// complete the reap on its own; the wait must suspend without burning CPU,
			// leaving the actor available for signaling/state. only the escalated
			// SIGKILL (which cannot be ignored) terminates the child.
			let process = ChildProcess(Command(absolutePath:"/bin/sh", arguments:["-c", "trap '' TERM; while :; do sleep 1; done"]), dataChannels:[
				STDOUT_FILENO: .write(.byo(fd:.init(rawValue:pipe.writing))),
				STDERR_FILENO: .write(.toNull),
				STDIN_FILENO: .read(.fromNull)
			])
			let runTask = Task { () -> ChildProcess.Exit in
				try await process.run(cancellationSignal:ChildProcess.defaultCancellationSignal)
			}
			let running = await waitUntilRunning(process)
			guard case .running(_) = running else {
				Issue.record("process never reached the running state")
				runTask.cancel()
				return
			}
			runTask.cancel()
			// while the cancelled wait is pending, the actor must stay responsive:
			// state reads must not block behind the reap, and signal delivery must
			// still interleave.
			try? await Task.sleep(for:.milliseconds(200))
			let midState = await process.state
			guard case .running(_) = midState else {
				Issue.record("expected the actor to stay responsive during the cancelled wait, but state was \(midState)")
				return
			}
			// escalate to SIGKILL, which proves signal(_:) interleaves during the wait.
			try await process.signal(SIGKILL)
			do {
				_ = try await runTask.value
				Issue.record("expected CancellationError, but the run produced a result")
			} catch is CancellationError {
				// expected. the signal was SIGTERM (ignored) then SIGKILL (escalation).
			} catch {
				Issue.record("expected CancellationError, but got \(error)")
			}
			let finalState = await process.state
			guard case .reaped(let exit) = finalState else {
				Issue.record("expected the process to be reaped after cancellation, but got \(finalState)")
				return
			}
			#expect(exit == .signal(SIGKILL), "expected termination by the escalated SIGKILL, but the process exited with \(exit)")
		}

		@Test("BYODataChannelTests :: caller descriptors survive the full process lifecycle",
			.timeLimit(.minutes(1))
		)
		func testByoOwnership() async throws {
			let pipe = try PosixPipe()
			defer {
				try? pipe.reading.closeFileHandle()
				try? pipe.writing.closeFileHandle()
			}
			let process = ChildProcess(Command(absolutePath:"/bin/echo", arguments:["ownership"]), dataChannels:[
				STDOUT_FILENO: .write(.byo(fd:.init(rawValue:pipe.writing))),
				STDERR_FILENO: .write(.toNull),
				STDIN_FILENO: .read(.fromNull)
			])
			let exit = try await process.run()
			#expect(exit == .code(0))
			#expect(await process.state == .reaped(.code(0)))
			#expect(__cswiftslash_fcntl_getfd(pipe.reading) >= 0, "swiftslash must never close the caller's reading descriptor")
			#expect(__cswiftslash_fcntl_getfd(pipe.writing) >= 0, "swiftslash must never close the caller's writing descriptor")
		}

		@Test("BYODataChannelTests :: task cancellation terminates and reaps with byo channels",
			.timeLimit(.minutes(1))
		)
		func testByoCancellation() async throws {
			let pipe = try PosixPipe()
			defer {
				try? pipe.reading.closeFileHandle()
				try? pipe.writing.closeFileHandle()
			}
			let process = ChildProcess(Command(absolutePath:"/bin/sleep", arguments:["30"]), dataChannels:[
				STDOUT_FILENO: .write(.byo(fd:.init(rawValue:pipe.writing))),
				STDERR_FILENO: .write(.toNull),
				STDIN_FILENO: .read(.fromNull)
			])
			let runTask = Task { () -> ChildProcess.Exit in
				try await process.run(cancellationSignal:ChildProcess.defaultCancellationSignal)
			}
			let running = await waitUntilRunning(process)
			guard case .running(_) = running else {
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
		}

		@Test("BYODataChannelTests :: invalid descriptor surfaces a dedicated spawn error",
			.timeLimit(.minutes(1))
		)
		func testByoInvalidDescriptor() async throws {
			let pipe = try PosixPipe()
			let badFD = pipe.writing
			try pipe.writing.closeFileHandle()
			defer {
				try? pipe.reading.closeFileHandle()
			}
			let process = ChildProcess(Command(absolutePath:"/bin/echo", arguments:["x"]), dataChannels:[
				STDOUT_FILENO: .write(.byo(fd:.init(rawValue:badFD))),
				STDERR_FILENO: .write(.toNull),
				STDIN_FILENO: .read(.fromNull)
			])
			await #expect(throws:ChildProcess.SpawnError.invalidByoFileDescriptor) {
				try await process.run()
			}
		}

		@Test("BYODataChannelTests :: FileDescriptor type semantics",
			.timeLimit(.minutes(1))
		)
		func testFileDescriptorType() async throws {
			let fd = FileDescriptor(rawValue:42)
			#expect(fd.rawValue == 42)
			#expect(fd == FileDescriptor(rawValue:42))
			#expect(fd != FileDescriptor(rawValue:43))
			var set:Set<FileDescriptor> = []
			set.insert(fd)
			set.insert(FileDescriptor(rawValue:42))
			#expect(set.count == 1, "equal descriptors must hash identically")
		}
	}
}
