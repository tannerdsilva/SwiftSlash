# 🔥 /SwiftSlash/ 🔥 

### Concurrent Shell Framework Built Entirely With Async/Await

Now fully documented with `swift-docc`! View the documentation on [the project's website](https://swiftslash.com/documentation/).

## Platform Support

 - Linux
 	- Fully supported since tag `1.0.0`
 	- Tests broken as of tag `3.0.0` - this is because Apple shipped Swift 5.5 without native support for async functions in `XCTestCase` on the Linux platform.
 	
 - MacOS
 	- Fully supported with release tag `3.1.0` or later
    - Tests passing   
     
## Why SwiftSlash?

**Efficiency, concurrency, simplicity.**

*SwiftSlash* was developed as a need to solve for the shortcomings of **all existing** shell frameworks. These frameworks include *SwiftCLI*, *Shell*, *ShellOut*, *ShellKit*, *Work*, and the highly popular *SwiftShell*. These frameworks have a cumulative star count of > 1,874 in their public GitHub repositories.

The Achilles heel of these existing frameworks is their internal use of *Foundation*'s own [*Process*](https://github.com/apple/swift-corelibs-foundation/blob/main/Sources/Foundation/Process.swift) class, which is a memory-heavy class that doesn't account for concurrent or complex use cases. For single, serialized executions, these frameworks will hold water (despite leaking memory). Under heavy use, however, all noted frameworks will struggle to stay afloat due to the shortcomings of *Process*.

*SwiftSlash* was designed intentionally from the ground up to address the shortcomings of these existing frameworks, and as such, deliberately doesn't use the *Process* class. As of version `3.0`, *SwiftSlash* is the first concurrent shell framework to be built entirely with Swift async/await concurrency paradigm. Up to versions `2.2.2`, *SwiftSlash* used Grand Central Dispatch as the internal concurrency paradigm.

With a fundamentally different engine serving as the heart of *SwiftSlash*, the objective improvements over other frameworks are as follows:

- `SwiftSlash` is the only known shell framework for Swift that will not leak memory with every command that has been executed.

- `SwiftSlash` is completely safe to use concurrently. By allowing shell commands to be run concurrently, **SwiftSlash can complete large quantities of non-sequential workloads in *fractions* of their expected time with serialized executions**.

- `SwiftSlash` can initialize and launch an external command with significantly greater efficiency than existing frameworks (both memory footprint and CPU impact). Similar performance improvements are seen in I/O handling from the `stdin`, `stdout`, and `stderr` streams. This is primarily because SwiftSlash was designed without the need to create an event loop for every process.

- `SwiftSlash` is structured to **ensure a secure execution environment**. In contrast: *Process* class has many security vulnerabilities, including file handle sharing with the child process and improper changing of the specified *working directory*.

- `SwiftSlash` deeply implements Swift's async/await concurrency paradigm at a fundamental level (**not** at the surface level). This allows for optimal resource sharing with other concurrent tasks that may be happening in your application.

- `SwiftSlash` automatically [reaps processes](https://www.geeksforgeeks.org/zombie-and-orphan-processes-in-c/) as soon as it is possible to do so, making it impossible for zombie/orphan processes to linger on your system. This means that your application does not necessarily need to wait for exit codes of the processes it launches.

- `SwiftSlash` is aware of the limited resources your process has been allocated by the system (primarily, file descriptors). It will not launch a command that your application does not have the resources to support. In such a case (under heavy concurrent use of SwiftSlash), processes requiring more resources than are available will be queued and launched when resources are freed.

Lastly, SwiftSlash is extremely straightforward to use, since it implements a rigorously simple public API. 

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
EXAMPLE: query the system for any zfs datasets that might be imported. 
			stdout: parse as lines
			stderr: unparsed, raw data will be sent through the stream as it becomes available

*/

//define the command you'd like to run
let zfsDatasetsCommand:Command = Command(bash:"zfs list -t dataset")

//pass the command structure to a new ProcessInterface. in this example, stdout will be parsed into lines with the lf byte, and stderr will be unparsed (raw data will be passed into the stream)
let zfsProcessInterface = ProcessInterface(command:zfsDatasetsCommand, stdout:.active(.lf), stderr:.active(.unparsedRaw))

//launch the process. if you are running many concurrent processes (using most of the available resources), this is where your process will be queued until there are enough resources to support the launched process.
let outputStreams = try await zfsProcessInterface.launch()

//handle lines of stdout as they come in
var datasetLines = [Data]()
for await outputLine in await zfsProcessInterface.stdout {
	print("dataset found: \( String(data:outputLine, encoding:.utf8) )")
	datasetLines += outputLine
}

//build the blob of stderr data if any was passed
var stderrBlob = Data()
for await stderrChunk in await zfsProcessInterface.stderr {
	print("\(stderrChunk.count) bytes were sent through stderr")
	stderrBlob += stderrChunk
}

//data can be written to stdin after a process is launched, like so...
zfsProcessInterface.write(stdin:"hello".data(using.utf8)!)

//retreive the exit code of the process. 
let exitCode = try await zfsProcessInterface.exitCode()

if (exitCode == 0) {
	//do work based on success
} else {
	//do work based on error
}
```

### License

SwiftSlash is available under the MIT license, and is provided without warranty. See LICENSE.

### Contact

Please contact `@tannerdsilva` on Twitter for inquiries.
