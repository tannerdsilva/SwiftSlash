import Testing
@testable import SwiftSlash
import __cswiftslash_posix_helpers
import SwiftSlashFHHelpers
import SwiftSlashFIFO

extension Tag {
	@Tag internal static var swiftSlashProcessTests:Self
}

extension SwiftSlashTests {
	@Suite("SwiftSlashEventTrigger", 
		.serialized,
		.tags(.swiftSlashProcessTests)
	)
	struct SwiftSlashProcessTests {
		@Test("SwiftSlashProcessTests :: exec validator", 
			.tags(.swiftSlashProcessTests)
		)
		func testExecValidator() async throws {
			#expect(__cswiftslash_execvp_safetycheck("/bin/echo") == 0)
		}
		@Test("SwiftSlashProcessTests", 
			.tags(.swiftSlashProcessTests)
		)
		func testSwiftSlashProcess() async throws {
			let randomInt = Int.random(in: 0...Int.max)
			let command = Command(absolutePath:"/bin/echo", arguments:["hello world \(randomInt)"])
			let process = ProcessInterface(command)
			let stdoutStream = await process[writer:STDOUT_FILENO]!

			switch stdoutStream {
				case .active(stream:let curStream, separator:let bytes):
					let iterator = curStream.makeAsyncIterator()
					let streamTask = Task {
						try await process.runChildProcess()
					}
					// fatalError("READ ERROR EARLY \(#file):\(#line)")
					parseLoop: while let curItem = await iterator.next() {
						let curString = String(bytes:curItem, encoding:.utf8)
						#expect(curString == "hello world \(randomInt)")
					}
					_ = try await streamTask.result.get()

				default:
					fatalError("SwiftSlash critical error :: stdout stream is not active.")
				
			}
			// let result = await streamTask.result
		}
	}
}