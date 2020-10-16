# 🔥 /SwiftSlash/ 🔥 

### A High-Performance Concurrent Shell Framework for Linux

## Why SwiftSlash?

SwiftSlash was developed as a need to solve for the shortcomings of all **existing** Swift shell frameworks. These frameworks are guilty of using `Foundation` (specifically the `Process` class within it) to launch commands. These frameworks include `Shell`, `ShellOut`, `ShellKit`, `Work`, and the highly popular `SwiftShell`. These frameworks have a cumulative star count of > 1,374 in their public GitHub repositories.

When compared to the frameworks listed above, SwiftSlash is a breed of its own.

SwiftSlash can manage large sets of concurrently executed processes with complete instructional safety. SwiftSlash captures data from these processes internally, and will parse bytestreams into lines before triggering downstream handler events. Line parsing is enabled by default and greatly reduces the complexity of parsing the data downstream in the process.

When comparing `SwiftSlash` with the widespread `Process` class backing many popular frameworks, the practical improvements of `SwiftSlash` speak for themselves.

- `SwiftSlash` does **NOT** leak memory, whereas `Process` will leak memory with ever command it runs. This is a significant downside for workloads that require many thousands of commands to be executed.

- `SwiftSlash` is safe to use concurrently and asynchronously, unlike `Process` class, which takes neither of these features into consideration. By allowing shell commands to be run concurrently rather than serially, `SwiftSlash` can complete large quantities of non-sequential workloads in **fractions** of their expected time.

- `SwiftSlash` can initialize and launch an external command with significantly greater efficiency than Foundation's `Process` class (both memory footprint and CPU impact). Similar performance improvements are seen in I/O handling from the `stdin`, `stdout`, and `stderr` streams.

- `SwiftSlash` is structured to **ensure a secure execution environment**. `Process` class has many security vulnerabilities, including file handle sharing with the executing process and improper changing of the specified *working directory*.

- `SwiftSlash` **can scale to massive workloads without consuming equally massive resources or time**.

## Getting Started

`Command` implements a convenience function `runSync()` which serves as a simple way to execute processes with minimal setup. In this function, proces I/O is captured and available after the process exits.
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

`ProcessInterface` is a powerful yet flexible class that serves as the base API for the SwfitSlash framework. Whether your process requires synchronous or asynchronous handling of buffered or unbuffered data, `ProcessInterface` is provides a consistent platform for building such workloads.

```
/* 
Example 1: Vanilla ProcessInterface Usage/Setup
	List all ZFS datasets on the system by running an external command. Buffer the standard output and error streams.
	Return the datasets if no error occurred.
*/
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

### License

SwiftSlash is available under the MIT license, and is provided without warranty. See LICENSE.

### Contact

Please contact `@tannerdsilva` on Twitter for inquiries.
