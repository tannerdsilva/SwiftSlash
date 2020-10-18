# 🔥 /SwiftSlash/ 🔥 

### A High-Performance Concurrent Shell Framework for Linux

## Why SwiftSlash?

SwiftSlash was developed as a need to solve for the shortcomings of **all existing** Swift shell frameworks. These frameworks include `Shell`, `ShellOut`, `ShellKit`, `Work`, and the highly popular `SwiftShell`. These frameworks have a cumulative star count of > 1,374 in their public GitHub repositories.

When comparing `SwiftSlash` with the widespread `Foundation.Process` class that backs the established shell frameworks listed above, the objective improvements of `SwiftSlash` speak for themselves.

- `SwiftSlash` does **NOT** leak memory, whereas `Process` will leak memory with every command it runs. This is a significant downside for workloads that require many thousands of commands to be executed.

- `SwiftSlash` is safe to use concurrently and asynchronously, unlike `Process` class, which takes neither of these features into consideration. By allowing shell commands to be run concurrently, **SwiftSlash can complete large quantities of non-sequential workloads in *fractions* of their expected time**.

- `SwiftSlash` can initialize and launch an external command with significantly greater efficiency than Foundation's `Process` class (both memory footprint and CPU impact). Similar performance improvements are seen in I/O handling from the `stdin`, `stdout`, and `stderr` streams.

- `SwiftSlash` is structured to **ensure a secure execution environment**. `Process` class has many security vulnerabilities, including file handle sharing with the executing process and improper changing of the specified *working directory*.

- `SwiftSlash` **can scale to massive workloads without consuming equally massive resources or time**.

- `SwiftSlash` does not have separate API classes for synchronous and asynchronous workloads.

SwiftSlash was designed to internalize the complexities of process-spawning as much as possible to simplify developer usage. Notably, SwiftSlash asynchronously captures stdout and stderr, and will parse these incoming bytestreams into lines (by default) before firing handler events. SwiftSlash also internalizes process-reaping under-the-hood. The developer is never asked to wait for the process to exit at any point in the process lifecycle. This feature ensures that zombie processes will never appear on your system, even the developers code is buggy. In light of this design choice, SwiftSlash offers more flexibility in handling process exits (when required). In addition to the traditional `waitForExitCode()` type function, SwiftSlash can also pass the exit code asynchronously to an exit handler of the developers choice.

## Getting Started

`Command` implements a convenience function `runSync()` which serves as a simple way to execute processes with no setup. In this function, proces I/O is captured as lines and available after the process exits.
```
import SwiftSlash

//define the command you'd like to run
let zfsVersionCommand:Command = Command(bash:"zfs --version")

//run the command in synchronous mode (wait for the process to exit - capture all process output)
let commandResult:CommandResult = try zfsVersionCommand.runSync()

//check the exit code
if commandResult.exitCode == 0 {

	//print the first line of output
	print("Found ZFS version: \(commandResult.stdout[0])")
}
```

## Using the Full API with ProcessInterface

`ProcessInterface` is a powerful yet flexible class that serves as the base API for the SwfitSlash framework. Whether your process requires synchronous or asynchronous handling of buffered or unbuffered data, `ProcessInterface` provides a consistent platform for building such workloads.

```
/* 
//define the command you'd like to run
let zfsDatasetsCommand:Command = Command(bash:"zfs list -t dataset")

//pass the command structure to a new ProcessInterface
let zfsProcessInterface = ProcessInterface(command:zfsDatasetsCommand)

//configure a line handler for the standard output of the process. lines are captured in the `datasetNames` array
var datasetNames = [String]()
zfsProcessInterface.stdoutHandler = { dataLine in
	if let asString = String(data:dataLine, encoding:.utf8) {
		datasetNames.append(asString)
	}
}

//configure a line handler for the standard error of the process. lines are captured in the `errors` array
var errors = [String]()
zfsProcessInterface.stderrHandler = { errorLine in
	if let asString = String(data:errorLine, encoding:.utf8) {
		errors.append(asString)
	}
}

//launch the process
try zfsProcessInterface.run()

//at this point, the code handlers above will begin firing as data begins streaming in from the process

//wait for the process to exit, capturing its exit code
let exitCode = zfsProcessInterface.waitForExitCode()

//return if success
if (exitCode == 0) {
	return datasetNames
}
```

Alternatively, an exit handler can be configured to capture the exit code when your process exits.

```
zfsProcessInterface.exitHandler = { exitCode in
	print("\(zfsProcessInterface.pid!) exited with the following code: \(exitCode)")
}
```

### License

SwiftSlash is available under the MIT license, and is provided without warranty. See LICENSE.

### Contact

Please contact `@tannerdsilva` on Twitter for inquiries.
