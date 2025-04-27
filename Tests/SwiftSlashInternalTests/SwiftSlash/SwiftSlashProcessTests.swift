import Testing
@testable import SwiftSlash
import __cswiftslash_posix_helpers
import SwiftSlashFHHelpers
import SwiftSlashFIFO
import class Foundation.FileManager

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
			.timeLimit(.minutes(1))
		)
		func testExecValidator() async throws {
			#expect(__cswiftslash_execvp_safetycheck("/bin/echo") == 0)
			#expect(__cswiftslash_execvp_safetycheck("/bin/.doesnotexist") != 0)
		}
		@Test("SwiftSlashProcessTests :: echo hello world unique random int", 
			.timeLimit(.minutes(1))
		)
		func testSwiftSlashProcess() async throws {
			let randomInt = Int.random(in: 0...Int.max)
			let command = Command(absolutePath:"/bin/echo", arguments:["hello world \(randomInt)"])
			let process = ProcessInterface(command)
			let stdoutStream = await process[writer:STDOUT_FILENO]!

			switch stdoutStream {
				case .active(stream:let curStream, separator:_):
					let iterator = curStream.makeAsyncIterator()
					let streamTask = Task {
						try await process.runChildProcess()
					}
					parseLoop: while let curItem = await iterator.next() {
						let curString = String(bytes:curItem.first!, encoding:.utf8)
						#expect(curString == "hello world \(randomInt)")
					}
					_ = try await streamTask.result.get()

				default:
					fatalError("SwiftSlash critical error :: stdout stream is not active.")
				
			}
			// let result = await streamTask.result
		}
		@Test("SwiftSlashProcessTests :: pwd output test", 
			.timeLimit(.minutes(1))
		)
		func testPwdOutput() async throws {
			let command = Command(absolutePath:"/bin/pwd", arguments:[])
			let process = ProcessInterface(command)
			let stdoutStream = await process[writer:STDOUT_FILENO]!

			switch stdoutStream {
				case .active(stream:let curStream, separator:_):
					let iterator = curStream.makeAsyncIterator()
					let streamTask = Task {
						try await process.runChildProcess()
					}
					parseLoop: while let curItem = await iterator.next() {
						let curString = String(bytes:curItem.first!, encoding:.utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
						#expect(curString != nil, "Expected non-nil output from pwd command")
						let currentDirectory = FileManager.default.currentDirectoryPath
						#expect(curString == currentDirectory, "Expected output from pwd command to match current directory path")
					}
					_ = try await streamTask.result.get()

				default:
					fatalError("SwiftSlash critical error :: stdout stream is not active.")
				
			}
		}
		/*@Test("SwiftSlashProcessTests :: argument counting", 
			.timeLimit(.minutes(1))
		)
		func testArgumentCounting() async throws {

			func testWithNumberOfArguments(_ count: Int) {
				var arguments = [String]()
				for i in 0..<count {
					arguments.append("arg\(i)")
				}
				let command = Command(absolutePath:"/bin/echo", arguments:["-c", "echo $#", "dummy"] + arguments)
				let process = ProcessInterface(command)
				let stdoutStream = await process[writer:STDOUT_FILENO]!
				switch stdoutStream {
					case .active(stream:let curStream, separator:let bytes):
						let iterator = curStream.makeAsyncIterator()
						let streamTask = Task {
							try await process.runChildProcess()
						}
						parseLoop: while let curItem = await iterator.next() {
							let curString = String(bytes:curItem, encoding:.utf8)
							let expectedCount = count + 1 // +1 for the "dummy" argument
							#expect(curString == "\(expectedCount)", "Expected \(expectedCount) arguments, got \(curString)")
						}
						_ = try await streamTask.result.get()

					default:
						fatalError("SwiftSlash critical error :: stdout stream is not active.")
				}
			}
			let command = Command(absolutePath:"/bin/echo", arguments:["-c", "echo $#", "dummy"])
			let process = ProcessInterface(command)
			#expect(process.command.arguments.count == 3, "Expected 3 arguments, got \(process.command.arguments.count)")
		}*/
	}
}