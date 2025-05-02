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
let processStatus = try Command("ps", arguments: ["aux"])
```

This will list all running processes on macOS or Linux.

## Running a Command

To execute a `Command` and wait for its completion, use the async `runSync()` method:

```swift
let result = try await processStatus.runSync()
```

`runSync()` returns a `CommandResult` containing:

* `exitCode`: the process exit code (`Int`).
* `stdout`: an array of `Data` chunks for standard output.
* `stderr`: an array of `Data` chunks for standard error.

## Handling Output

Convert `Data` to `String` using `String(decoding:as:)`:

```swift
if result.exitCode == 0 {
    let firstLine = String(decoding: result.stdout.first ?? Data(), as: .utf8)
    print("Output: \(firstLine)")
} else {
    let errors = result.stderr
        .map { String(decoding: $0, as: .utf8) }
        .joined(separator: "\n")
    print("Error: \(errors)")
}
```

## Complete Example

```swift
task {
    let versionResult = try await Command("zfs", arguments: ["--version"]).runSync()
    if versionResult.exitCode == 0 {
        let version = String(
            decoding: versionResult.stdout.first ?? Data(),
            as: .utf8
        )
        print("ZFS version: \(version)")
    } else {
        print("Failed to get ZFS version")
    }
}
```
