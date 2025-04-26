import Testing
@testable import SwiftSlash
import __cswiftslash_posix_helpers
import SwiftSlashFHHelpers
import SwiftSlashFIFO

extension Tag {
	@Tag internal static var SwiftSlashProcessTests:Self
}

extension SwiftSlashTests {
	@Suite("SwiftSlashEventTrigger", 
		.serialized,
		.tags(.swiftSlashFIFO)
	)
	struct SwiftSlashProcessTests {
		@Test("SwiftSlashProcessTests", 
			.tags(.swiftSlashFIFO)
		)
		func testSwiftSlashProcess() async throws {
			let command = Command(absolutePath:"/bin/zsh", arguments:["-c", "pwd"])
			let process = ProcessInterface(command)
			let stdoutStream = await process[writer:STDERR_FILENO]!
			let streamTask = Task {
				switch stdoutStream {
					case .active(stream:let curStream, separator:let bytes):
						// fatalError("READ ERROR EARLY")
						for await curItem in curStream {
							fatalError("READ ERROR")
							let curString = String(bytes:curItem, encoding:.utf8)
							#expect(curString == "hello world")
						}
					default:
						fatalError("SwiftSlash critical error :: stdout stream is not active.")
					
				}
			}
			try await process.runChildProcess()
			let result = await streamTask.result
		}
	}
}