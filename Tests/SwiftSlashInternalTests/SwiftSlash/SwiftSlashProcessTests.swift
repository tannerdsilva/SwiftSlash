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
			let command = Command(absolutePath:"/usr/bin/bash", arguments:["-c", "/usr/bin/pwd"])
			let process = ProcessInterface(command)
			// await process[writer:STDIN_FILENO] = nil
			let stdoutStream = await process[writer:STDOUT_FILENO]!
			// let asyncIterator = stdoutStream.makeAsyncIterator()

			switch stdoutStream {
				case .active(stream:let curStream, separator:let bytes):
					let iterator = curStream.makeAsyncIterator()
					let streamTask = Task {
						try await process.runChildProcess()
					}
					// fatalError("READ ERROR EARLY \(#file):\(#line)")
					while let curItem = await iterator.next() {
						let curString = String(bytes:curItem, encoding:.utf8)
						#expect(curString == "hello world")
						fatalError("'\( curString ?? "nil")'")
					}
					fatalError("READ DONE \(#file):\(#line)")
					_ = try await streamTask.result.get()
					// let newState: ProcessInterface.State = await process.state
					// #expect(newState == .exited(0))

				default:
					fatalError("SwiftSlash critical error :: stdout stream is not active.")
				
			}
			// let result = await streamTask.result
		}
	}
}