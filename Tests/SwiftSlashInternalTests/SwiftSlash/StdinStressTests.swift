import Testing
@testable import SwiftSlash
import __cswiftslash_posix_helpers
import SwiftSlashFHHelpers

extension Tag {
	@Tag internal static var swiftSlashStdinStress:Self
}

/// adversarial coverage for the stdin write path (LINUX_STDIN_EOF_DEADLOCK.md).
/// the two regression tests prove EOF delivery and streamed multi-chunk writes;
/// these prove the failure modes around them: a child that exits mid-stream
/// (SIGPIPE must be suppressed so the parent survives), the once-only SIGPIPE
/// suppression itself, and full-pipe backpressure where the write loop parks on
/// the writability signal and resumes on full->space transitions.
extension SwiftSlashTests {
	@Suite("SwiftSlashStdinStress",
		.serialized,
		.tags(.swiftSlashStdinStress)
	)
	struct SwiftSlashStdinStress {

		@Test("SwiftSlashProcessTests :: parent survives a child that exits mid-stream",
			.timeLimit(.minutes(1))
		)
		func childExitsMidStream() async throws {
			// the child reads one line and exits with 7. the parent keeps a large
			// stream buffered behind it: some of those writes race the child's
			// exit. the parent must survive (SIGPIPE suppressed) and run() must
			// return the child's exit instead of crashing or hanging.
			let command = Command(absolutePath:"/bin/sh", arguments:["-c", #"IFS= read -r _ && exit 7"#])
			let process = ChildProcess(command)
			async let exitResult = process.run()
			try process.stdin.yield([UInt8]("hello\n".utf8))
			let big = [UInt8](repeating: 65, count: 300_000)
			try? process.stdin.yield(big)
			try await Task.sleep(for:.milliseconds(400))
			process.stdin.closeDataChannel()
			let exit = try await exitResult
			#expect(exit == .code(7), "expected the child's exit code to surface, got \(exit)")
		}

		@Test("SwiftSlashProcessTests :: SIGPIPE is suppressed once a child has been launched",
			.timeLimit(.minutes(1))
		)
		func sigpipeSuppressedAfterLaunch() async throws {
			// the first launch installs the suppression. a subsequent write to a
			// pipe whose read end is gone must surface EPIPE (.error_pipe)
			// instead of terminating the process with SIGPIPE.
			let p1 = ChildProcess(Command(absolutePath:"/bin/echo"))
			_ = try await p1.run()
			let dead = try PosixPipe()
			try dead.reading.closeFileHandle()
			var threwPipe = false
			do {
				_ = try dead.writing.writeFH(singleByte:0x41)
			} catch FileHandleError.error_pipe {
				threwPipe = true
			}
			#expect(threwPipe, "expected the write to a readerless pipe to surface EPIPE")
		}

		@Test("SwiftSlashProcessTests :: backpressure through full->space transitions",
			.timeLimit(.minutes(1))
		)
		func backpressureFullToSpace() async throws {
			// a child that reads stdin slowly to completion. the payload is far
			// larger than the pipe buffer, so the write loop must park on the
			// writability signal repeatedly and resume on full->space transitions.
			let command = Command(absolutePath:"/bin/sh", arguments:["-c", #"i=0; while IFS= read -r _x; do i=$((i+1)); [ $((i%100)) -eq 0 ] && sleep 0.002; done; exit 0"#])
			let process = ChildProcess(command)
			async let exitResult = process.run()
			let line = Array("0123456789abcdef\n".utf8)
			// well above the 64k pipe buffer, so the write loop must fill, park,
			// and resume on full->space transitions several times.
			let payload = (0..<8000).flatMap { _ in line }
			try process.stdin.yield(payload)
			process.stdin.closeDataChannel()
			let exit = try await exitResult
			#expect(exit == .code(0), "expected the slow-reader child to finish via backpressure, got \(exit)")
		}
	}
}
