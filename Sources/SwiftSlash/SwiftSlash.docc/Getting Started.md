# Getting Started

This guide walks through running your first commands with SwiftSlash using the convenient `Command` and `CommandResult` APIs.

## Installation

Add SwiftSlash to your project via Swift Package Manager:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/tannerdsilva/SwiftSlash.git", "4.0.0"..<"5.0.0"),
]
```

Then import SwiftSlash:

```swift
import SwiftSlash
```

## Defining a Command

A `Command` represents an external executable plus its arguments:

```swift
// this initializer throws because SwiftSlash may theoretically fail to find the "ps" executable
let commandToLaunch = try Command("ps", arguments:["aux"])
```

This `Command` will list all currently running processes on the host system.

## Running a Command

To execute a `Command` and wait for its completion, use the `runSync()` function:

```swift
let result = try await commandToLaunch.runSync()
```

`runSync()` returns a `SyncResult` containing:

* `exit`: an enum specifying the exit result of the process. A process can either exit with an exit code, or exit with an uncaught signal code.
* `stdout`: an array of byte "lines" (`[UInt8]`) that were parsed from the standard output stream.
* `stderr`: an array of byte "lines" (`[UInt8]`) that were parsed from the standard error stream.

## Handling Output

Convert `[UInt8]` lines to `String` using `String(decoding:as:)`:

```swift
if result.exit == .code(0) {
    let firstLine = String(bytes:result.stdout.first!, encoding:.utf8)
    print("Output: \(firstLine)")
} else {
    // handle errors here as necessary
    print("There was an error. STDERR contents below\n==========")
    for curLine in result.stderr {
    	if let asString = String(bytes:curLine, encoding:.utf8) {
    		print("\(asString)")
    	} else {
    		print("Could not convert to string. This line contains \(curLine.count) bytes.")
    	}
    }
}
```

## Complete Example

```swift
task {
    let versionResult = try await Command("zfs", arguments: ["--version"]).runSync()
    if versionResult.exitCode == 0 {
        let version = String(bytes:versionResult.stdout.first!, encoding:.utf8)
        print("ZFS version: \(version)")
    } else {
        print("Failed to get ZFS version")
    }
}
```

## Advanced Usage

To unlock the full capability and features available in SwiftSlash (including more complex async workloads that happen during runtime), you will need to interact directly with a ``SwiftSlash/ChildProcess`` instance.
