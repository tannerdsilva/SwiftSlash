# 🔥 /SwiftSlash/ 🔥 

### Concurrent Shell Framework Built Entirely With Async/Await

## Platform Support

 - Linux
 	- Fully supported
 	- Tests broken as of `3.0.0` - this is because Apple shipped Swift 5.5 without native support for async functions in `XCTestCase` on the Linux platform. Options are being explored to hack this functionality together again: [see issue #5](https://github.com/tannerdsilva/SwiftSlash/issues/5).
 	
 - MacOS
 	- Successful builds in branch `macosCompat`. Buggy at this time, still under development.
 	- Functionality falls appart with heavy concurrency (excess of 10 concurrent processes).
 	- Native XCTestCase is functional on MacOS Monterey. Tests do not always pass which is why MacOS support has not been tagged in the `master` branch at this time.

## Why SwiftSlash?

**Efficiency, concurrency, simplicity.**

*SwiftSlash* was developed as a need to solve for the shortcomings of **all existing** shell frameworks. These frameworks include *SwiftCLI*, *Shell*, *ShellOut*, *ShellKit*, *Work*, and the highly popular *SwiftShell*. These frameworks have a cumulative star count of > 1,874 in their public GitHub repositories.

The Achilles heel of these existing frameworks is their internal use of *Foundation*'s own [*Process*](https://github.com/apple/swift-corelibs-foundation/blob/main/Sources/Foundation/Process.swift) class, which is a memory-heavy class that doesn't account for concurrent or complex use cases. For single, serialized executions, these frameworks will hold water (despite leaking memory). Under heavy use, however, all noted frameworks will struggle to stay afloat due to the shortcomings of *Process*.

*SwiftSlash* was designed intentionally from the ground up to address the shortcomings of these existing frameworks, and as such, deliberately doesn't use the *Process* class. As of version `3.0`, *SwiftSlash* is the first concurrent shell framework to be built entirely with Swift async/await concurrency paradigm [1]. Up to versions `2.2.2`, *SwiftSlash* used Grand Central Dispatch as the internal concurrency paradigm.

With a fundamentally different engine serving as the heart of *SwiftSlash*, the objective improvements over other frameworks are as follows:

- `SwiftSlash` is the only known shell framework for Swift that will not leak memory with every command that has been executed.

- `SwiftSlash` is completely safe to use concurrently. By allowing shell commands to be run concurrently, **SwiftSlash can complete large quantities of non-sequential workloads in *fractions* of their expected time with serialized executions**.

- `SwiftSlash` can initialize and launch an external command with significantly greater efficiency than existing frameworks (both memory footprint and CPU impact). Similar performance improvements are seen in I/O handling from the `stdin`, `stdout`, and `stderr` streams. This is primarily because SwiftSlash was designed without the need to create an event loop for every process.

- `SwiftSlash` is structured to **ensure a secure execution environment**. In contrast: *Process* class has many security vulnerabilities, including file handle sharing with the child process and improper changing of the specified *working directory*.

- `SwiftSlash` deeply implements Swift's async/await concurrency paradigm at a fundamental level (**not** at the surface level). This allows for optimal resource sharing with other concurrent tasks that may be happening in your application.

- `SwiftSlash` automatically [reaps processes](https://www.geeksforgeeks.org/zombie-and-orphan-processes-in-c/) as soon as it is possible to do so, making it impossible for zombie/orphan processes to linger on your system. This means that your application does not necessarily need to wait for exit codes of the processes it launches.

Lastly, SwiftSlash is extremely straightforward to use, since it implements a rigorously simple public API. All of SwiftSlash's functionality can be utilized with a single structure (`Command`) and a single actor (`ProcessInterface`). For added convenience, a third structure exists in the public API to fully encapsulate the result of an exited command: `CommandResult`.

## Getting Started

`Command` implements a convenience function `runSync()` which serves as a simple way to execute processes with no setup or I/O handling.

```
import SwiftSlash

// EXAMPLE: check the systems ZFS version and print the first line of the output

let commandResult:CommandResult = try await Command(bash:"zfs --version").runSync()

//check the exit code
if commandResult.exitCode == 0 {

	//print the first line of output
	print("Found ZFS version: \( String(data:commandResult.stdout[0], encoding:.utf8) )")
}

```

## Full Functionality through ProcessInterface

`ProcessInterface` is a powerful yet flexible class that serves as the base API for the SwfitSlash framework. Whether your process requires synchronous or asynchronous handling of parsed or unparsed data, `ProcessInterface` provides a consistent platform for defining such requirements.

```
/* 
EXAMPLE: query the system for any zfs datasets that might be imported. write 
			stdout: parse as lines
			stderr: unparsed, raw data will be sent through the stream as it becomes available

*/

//define the command you'd like to run
let zfsDatasetsCommand:Command = Command(bash:"zfs list -t dataset")

//pass the command structure to a new ProcessInterface. in this example, stdout will be parsed into lines with the lf byte, and stderr will be unparsed (raw data will be passed into the stream)
let zfsProcessInterface = ProcessInterface(command:zfsDatasetsCommand, stdoutParseMode:.lf, stderrParseMode:.immediate)

//launch the process. if any data needs to be passed into stdin upon launch, it can be passed into the launch() function
let outputStreams = try await zfsProcessInterface.launch()

//handle lines of stdout as they come in
var datasetLines = [Data]()
for await outputLine in outputStreams.stdout {
	print("dataset found: \( String(data:outputLine, encoding:.utf8) )")
	datasetLines += outputLine
}

//build the blob of stderr data if any was passed
var stderrBlob = Data()
for await stderrChunk in outputStreams.stderr {
	print("\(stderrChunk.count) bytes were sent through stderr")
	stderrBlob += stderrChunk
}

//data can be written to stdin after a process is launched, like so...
zfsProcessInterface.write(stdin:"hello".data(using.utf8)!)

//retreive the exit code of the process. 
let exitCode = await zfsProcessInterface.exitCode()

if (exitCode == 0) {
	//do work based on success
} else {
	//do work based on error
}
```

NOTE: Given the asynchronous nature of this framework (no thread blocking while waiting for exit codes), and to prevent conflicts with *SwiftSlash*'s internal [process-reaping](https://www.geeksforgeeks.org/zombie-and-orphan-processes-in-c/) mechanism, `ProcessInterface` intentionally hides the spawned process ID from the public-facing API. This helps enforce the runtime contract of Swifts concurrency model (no thread blocking), and also ensures an application developer cannot capture an exit code before *SwiftSlash* can. That being said, `ProcessInterface` still provides functions for sending signals and retrieving exit codes. This addresses the biggest needs to access the PID directly.

### License

SwiftSlash is available under the MIT license, and is provided without warranty. See LICENSE.

### Contact

Please contact `@tannerdsilva` on Twitter for inquiries.
