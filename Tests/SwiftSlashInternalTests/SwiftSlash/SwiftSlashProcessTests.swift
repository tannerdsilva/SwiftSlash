import Testing
@testable import SwiftSlash
import __cswiftslash_posix_helpers
import SwiftSlashFHHelpers
import SwiftSlashFIFO
import SwiftSlashFuture
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

		@Test("SwiftSlashProcessTests :: echo path search test", 
			.timeLimit(.minutes(1))
		)
		func testPathSearch() async throws {
			_ = try Command("echo")
		}
		@Test("SwiftSlashProcessTests :: echo hello world unique random int", 
			.timeLimit(.minutes(1))
		)
		func testSwiftSlashProcess() async throws {
			let randomInt = Int.random(in: 0...Int.max)
			let command = Command(absolutePath:"/bin/echo", arguments:["hello world \(randomInt)"])
			let process = ChildProcess(command)
			async let exitResult = process.run()
			let outTask = Task {
				var buildLines = [[UInt8]]()
				parseLoop: for await curItem in process.stdout {
					buildLines.append(contentsOf:curItem)
				}
				return buildLines
			}
			let errTask = Task {
				var errCount = 0
				for await curItem in process.stderr {
					errCount += curItem.count
				}
				return errCount
			}
			#expect(await outTask.result.get() == [Array("hello world \(randomInt)".utf8)], "expected output to match input string")
			#expect(await errTask.result.get() == 0, "expected no errors from child process")
			#expect(try await exitResult == .code(0))
		}
		@Test("SwiftSlashProcessTests :: pwd output test", 
			.timeLimit(.minutes(1))
		)
		func testPwdOutput() async throws {
			let command = Command(absolutePath:"/bin/pwd")
			let process = ChildProcess(command)
			let stdoutStream = process[writer:STDOUT_FILENO]!

			switch stdoutStream {
				case .toParentProcess(stream:let curStream, separator:_):
					let streamTask = Task {
						try await process.run()
					}
					parseLoop: for await curItem in curStream {
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

		@Test("SwiftSlashProcessTests :: exit code via piped input test (complete 0-255)", 
			.timeLimit(.minutes(1))
		)
		func exitCodeTest() async throws {
			func runExitCodeProcess(expectedExitCode:UInt8) async throws {
				// this is a special command that will read a line of input and then exit with that code. the input line must be a valid exit number.
				let command = Command(absolutePath:"/bin/sh", arguments:["-c", #"IFS= read num && exit "$num""#])
				let process = ChildProcess(command)
				let stdInWriteStream = process[reader:STDIN_FILENO]!
				switch stdInWriteStream {
					case (.fromParentProcess(stream:let inputStream)):
						// launch the child process.
						async let processResult = process.run()
						// write a line of input to the child process.
						let inputString = "\(expectedExitCode)\n"
						let inputData = [UInt8](inputString.utf8)
						try inputStream.yield(inputData)
						// wait for the input to be written
						let exitResult = try await processResult
						#expect(exitResult == .code(Int32(expectedExitCode)), "expected child process to exit with code \(ChildProcess.Exit.code(Int32(expectedExitCode))) but instead exited with \(exitResult)")

					default:
						fatalError("SwiftSlash critical error :: stdin or stdout stream is not active.")
				}
			}
			for i in 0..<255 {
				try await runExitCodeProcess(expectedExitCode:UInt8(i))
			}
		}

		@Test("SwiftSlashProcessTests :: piped input test", 
			.timeLimit(.minutes(1))
		)
		func writeInputToChildProcess() async throws {
			// this is a special command that will read a line of input and then print it out, exiting after the line is printed.
			let command = Command(absolutePath:"/bin/sh", arguments:["-c", #"IFS= read line && printf "%s\n" "$line"; exit 0"#])

			let process = ChildProcess(command)
			let stdInWriteStream = process[reader:STDIN_FILENO]!
			let stdoutStream = process[writer:STDOUT_FILENO]!
			switch (stdInWriteStream, stdoutStream) {
				case (.fromParentProcess(stream:let inputStream), .toParentProcess(stream:let outputStream, separator:_)):
					// launch the child process.
					let streamTask = Task {
						try await process.run()
					}
					// write a line of input to the child process.
					let inputString = "Hello from parent process\n"
					let inputData = [UInt8](inputString.utf8)
					try inputStream.yield(inputData)
					var foundItems:size_t = 0
					parseLoop: for await curItem in outputStream {
						guard curItem.count < 2 else {
							break parseLoop
						}
						defer {
							foundItems += 1
						}
						let curString = String(bytes:curItem.first!, encoding:.utf8)!
						#expect(curString == "Hello from parent process", "expected output to match input string")
					}
					#expect(foundItems == 1, "expected to find exactly one output item from child process")
					_ = try await streamTask.result.get()
					

				default:
					fatalError("SwiftSlash critical error :: stdin or stdout stream is not active.")
			}
		}

		@Test("SwiftSlashProcessTests :: piped input test with exit code", 
			.timeLimit(.minutes(1))
		)
		func testRunSync() async throws {
			let newCommand = Command(absolutePath:"/bin/pwd")
			// let newCommand = Command(absolutePath:"/bin/sh", arguments:["-c", #"i=0; while [ "$i" -lt 10 ]; do echo "your string"; i=$((i+1)); done; exit 0"#])
			let result = try await newCommand.runSync()
			// #expect(result.exit == .code(0), "expected exit code to be 0, but got \(result.exit)")
			// #expect(result.stdout.count == 10, "expected 10 lines of output, but got \(result.stdout.count)")
			// for line in result.stdout {
			// 	let curString = String(bytes:line, encoding:.utf8)
			// 	#expect(curString != nil, "expected non-nil output from command")
			// 	if let curString = curString {
			// 		#expect(curString == "Hello from the other shell!", "expected output to match input string")
			// 	} else {
			// 		fatalError("SwiftSlash critical error :: stdout stream is not active.")
			// 	}
			// }
		}
	}
}
