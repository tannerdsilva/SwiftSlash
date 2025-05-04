# SwiftSlash 🚀

[![Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftannerdsilva%2FSwiftSlash%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/tannerdsilva/SwiftSlash) [![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftannerdsilva%2FSwiftSlash%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/tannerdsilva/SwiftSlash)

> **Dependency-free, high-performance concurrent shell framework for Swift 6.0+**

SwiftSlash 4.0 is a pure-Swift library (zero external dependencies) designed for rock-solid reliability and speed. Its internal engine ensures:

* 🔒 **Memory Safety**: Automatic cleanup of file descriptors and subprocesses guarantees no memory leaks or zombie processes.
* ⚡ **Blazing Performance**: Fast process startup, I/O streaming, and internal scheduling without per-process event loops.
* 🔄 **True Concurrency**: Run hundreds or thousands of shell commands in parallel, leveraging Swift’s async/await for minimal overhead.
* 🛡 **Secure Execution**: Isolated handles and controlled working-directory management ensure a hardened runtime.
* 📦 **Type-Safe API**: Leveraging Swift 6.0/6.1’s advanced type system for compile-time correctness and clear intent.

## 📚 Documentation

Full DocC documentation is available at [swiftslash.com/documentation](https://swiftslash.com/documentation/).

## 🚀 Getting Started

Add SwiftSlash to your project via Swift Package Manager:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/tannerdsilva/SwiftSlash.git", from: "4.0.0"),
]
```

Then import and execute a simple command:

```swift
import SwiftSlash

// Example: list contents of /usr/bin
task {
    let result = try await Command("ls", arguments: ["-l", "/usr/bin"]).run()
    let output = String(decoding: result.stdout, as: UTF8.self)
    print(output)
}
```

## 🛠️ Advanced Usage

SwiftSlash also supports mapping custom I/O streams to additional file descriptors beyond `stdin`, `stdout`, and `stderr`. This makes it simple to drive processes that require multiple input or output channels without resorting to lower-level POSIX calls. You can attach readers and writers to any file descriptor number:

```swift
import SwiftSlash

task {
    let cmd = Command("my-radical-tool", arguments: ["--mode", "parallel"]);
    let proc = ChildProcess(
        command: cmd,
        stdin: .active(.raw),
        stdout: .active(.lineDelimited),
        stderr: .active(.raw),
        extraStreams: [3: .active(.lineDelimited), 4: .active(.raw)]
    )

    try await proc.launch()

    // Read from the extra output stream on fd 3
    for await chunk in proc.extraReaders[3]! {
        print("Channel 3: \(String(decoding: chunk, as: UTF8.self))")
    }

    // Write to the extra input stream on fd 4
    let inputData = "feed data".data(using: .utf8)!
    try await proc.extraWriters[4]?(inputData)

    let code = try await proc.exitCode()
    print("Exit code: \(code)")
}
```

For fine-grained control over I/O, timeouts, and concurrency, use `ChildProcess`:

```swift
import SwiftSlash

task {
    let cmd = Command("zfs", arguments: ["list", "-t", "dataset"]);
    let proc = ChildProcess(
        command: cmd,
        stdout: .active(.lineDelimited),
        stderr: .active(.raw)
    )

    try await proc.launch()

    for await line in proc.stdout {
        print("Dataset: \(String(decoding: line, as: UTF8.self))")
    }

    let errors = try await proc.stderr.reduce(into: Data()) { $0.append($1) }
    let code   = try await proc.exitCode()
    print("Exit code: \(code)")
}
```

## 🤝 Contributing

We welcome bug reports, feature requests, and pull requests. Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## 📄 License

SwiftSlash is released under the MIT License. See [LICENSE](LICENSE) for details.

## 📬 Contact

Stay up to date or ask questions on Twitter: [@tannerdsilva](https://twitter.com/tannerdsilva)
