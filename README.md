# 🔥 SwiftSlash 🔥 

### A High-Performance Concurrent Shell Framework for Linux

## Getting Started
```
import SwiftSlash
let zfsVersionCommand:Command = Command(bash:"zfs --version")
let commandResult:CommandResult = try zfsVersionCommand.runSync()
if commandResult.succeeded {
	print("Found ZFS version: \(commandResult.stdout[0])")
}
```

## Using the Full API with ProcessInterface
```
import SwiftSlash
let zfsDatasetsCommand:Command = Command(bash:"zfs list -t dataset")
let zfsProcessInterface = ProcessInterface(command:zfsDatasetsCommand)
var datasetNames = [String]()
zfsProcessInterface.stdoutHandler = { data in
	if let asString = String(data:data, encoding:.utf8) {
		datasetNames.append(asString)
	}
}
try zfsProcessInterface.run()
let exitCode = zfsProcessInterface.waitForExitCode()
return datasetNames
```

## Why SwiftSlash?

SwiftSlash was born from a need to interface with large sets of concurrently executed processes with complete instructional safety. Furthermore, SwiftSlash was born with an uncompromising desire for time efficiency.

While other frameworks (such as `SwiftShell` and the `Foundation` framework that underlies it) provide shell-like functionality in Swift, **these frameworks were not designed for demanding workloads**. SwiftShell is only guaranteed to be safe when processes are executed serially in a single thread. This is a technical limitation that severely limits `SwiftShell`'s ability to scale. This limitation is a particular concern for environments where multiple processes need to be running for a prolonged periods of time. SwiftSlash was designed with these concerns in mind.

With full concurrency as requirement, SwiftSlash was designed to provide uncompromising stability with a simple, single-class API.

When comparing `SwiftSlash` with the popular `SwiftShell` framework, the practical improvements of `SwiftSlash` speak for themselves.

- `SwiftSlash` does **NOT** leak memory, whereas SwiftShell will leak memory with ever command it runs. This is a significant downside for workloads that require many thousands of commands to be executed.

- `SwiftSlash` is safe to use concurrently and asynchronously, unlike `Process` class, which takes neither of these features into consideration. By allowing shell commands to be run concurrently rather than serially, `SwiftSlash` can complete large quantities of non-sequential workloads in **fractions** of their expected time.

- `SwiftSlash` can initialize and launch an external command with significantly greater computational and memory efficiency than Foundation's `Process` class. Similar performance improvements are seen in I/O handling from the `stdin`, `stdout`, and `stderr` streams. For industrial workloads, better performance means a faster time to completion. For mobile workloads, better performance means better battery life.

- `SwiftSlash` has the necessary infrastructure to **ensure a secure execution environment**. `Process` class has many security vulnerabilities, including file handle sharing with the executing process and improper changing of the specified *current directory*.

- `SwiftSlash` **can scale to massive workloads without consuming equally massive resources or time**. 

By executing shell commands concurrently rather than serially, one could see speedup multiples of *up to* 250x - *workload dependent*

Please contact `@tannerdsilva` on Twitter for inquiries.
