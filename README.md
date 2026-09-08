# SwiftSlash 🚀

[![Swift Compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftannerdsilva%2FSwiftSlash%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/tannerdsilva/SwiftSlash) [![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Ftannerdsilva%2FSwiftSlash%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/tannerdsilva/SwiftSlash)

> **Dependency-free, high-performance concurrent shell framework for Swift 6.0+**

SwiftSlash 4.0 is a pure-Swift library (zero external dependencies) designed for rock-solid reliability and speed. Its internal engine ensures:

* 🔒 **Memory Safety**: Automatic cleanup of file descriptors and subprocesses guarantees no memory leaks or zombie processes.
* ⚡ **Blazing Performance**: Fast process startup, I/O streaming, and internal scheduling without per-process event loops.
* 🔄 **True Concurrency**: Run hundreds or thousands of shell commands in parallel, leveraging Swift’s async/await for minimal overhead.
* 🛡 **Secure Execution**: Isolated handles and controlled working-directory management ensure a hardened runtime.
* 📦 **Type-Safe API**: Leveraging Swift 6.0/6.1’s advanced type system for compile-time correctness and clear intent.
* 🛑 **Native Task Cancellation**: Cancelling the awaiting `Task` terminates the child process and its process group, reaps all resources, and surfaces `CancellationError` — no orphaned or zombie processes.

## 📚 Documentation

Full DocC documentation is available at [swiftslash.com/documentation](https://swiftslash.com/documentation/).

## 🔌 Bring Your Own Data Channels

Don't want SwiftSlash's built-in stdio pipeline for a given process? Hand it a file descriptor you already own — SwiftNIO, sockets, PTYs, or anything else — and SwiftSlash binds it to the child and stays out of the data path entirely. Reaping and cancellation remain fully intact.

```swift
import Foundation
import SwiftSlash

let pipe = Pipe()
let child = ChildProcess(
    try Command("/bin/cat"),
    dataChannels: [
        STDIN_FILENO: .read(.byo(fd: .init(rawValue: pipe.fileHandleForReading.fileDescriptor))),
        STDOUT_FILENO: .write(.byo(fd: .init(rawValue: pipe.fileHandleForWriting.fileDescriptor))),
        STDERR_FILENO: .write(.byo(fd: .init(rawValue: pipe.fileHandleForWriting.fileDescriptor)))
    ]
)
async let exit = child.run()
// ... drive `pipe` with SwiftNIO (or anything else) — SwiftSlash never touches it.
```

See the [BYO Data Channels](https://swiftslash.com/documentation/swiftslash/bring-your-own-data-channels) article for the full ownership contract.

## 🤝 Contributing

We welcome bug reports, feature requests, and pull requests.

## 📄 License

SwiftSlash is released under the MIT License. See [LICENSE](LICENSE) for details.

## 📬 Contact

Stay up to date or ask questions on Twitter: [@tannerdsilva](https://twitter.com/tannerdsilva)