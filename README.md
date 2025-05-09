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

## 🤝 Contributing

We welcome bug reports, feature requests, and pull requests.

## 📄 License

SwiftSlash is released under the MIT License. See [LICENSE](LICENSE) for details.

## 📬 Contact

Stay up to date or ask questions on Twitter: [@tannerdsilva](https://twitter.com/tannerdsilva)