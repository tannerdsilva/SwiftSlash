# SwiftSlash `Command`

The `Command` structure encapsulates everything needed to define and configure an external process before execution.

## Properties

- **`executable: String`**

  * Absolute path to the executable, or a program name resolved via system `PATH`.
  * Must point to a valid executable on the host system.

- **`arguments: [String]`**

  * Ordered list of command-line arguments to pass to the executable.
  * Each element corresponds to a separate token as you would type in the shell.

- **`environment: [String: String]`**

  * Key-value pairs for environment variables available to the process.
  * Use this to customize PATH, locale, or other runtime settings.

- **`workingDirectory: String?`**

  * Optional path to set as the process’s current directory before launch.
  * Defaults to the parent process’s working directory if omitted.

## Usage

A `Command` is purely a definition—it does not execute on its own. To run a command:

1. **With a convenience method:**

   ```swift
   let result = try await Command("ls", arguments: ["-al"]).runSync()
   ```

   * This shortcut creates an internal `ProcessInterface` and waits for completion.

2. **With `ProcessInterface` for more control:**

   ```swift
   let cmd = try Command("ps", arguments: ["aux"])
   let interface = ProcessInterface(
       command: cmd,
       stdout: .active(.lineDelimited),
       stderr: .active(.raw)
   )
   try await interface.launch()
   // ... handle streams, exitCode, etc.
   ```

## Discussion

Use `Command` to build a launch plan for any external tool, script, or binary. Customize its arguments, environment, and working directory independently of execution. For quick tasks, `runSync()` is the simplest path. When you need streaming I/O, timeouts, or advanced scheduling, pass your `Command` into a `ProcessInterface`.

## Available Initializers & Methods

### Initializers

* **Direct Paths**

  * `init(absolutePath: String, arguments: [String], environment: [String: String] = [:], workingDirectory: String? = nil)`
  * `init(_ name: String, arguments: [String], environment: [String: String] = [:], workingDirectory: String? = nil)`

* **Shell Wrappers**

  * `init(bash command: String, environment: [String: String] = [:], workingDirectory: String? = nil)`
  * `init(zsh command: String, environment: [String: String] = [:], workingDirectory: String? = nil)`

### Execution

* **`func runSync() async throws -> CommandResult`**

  * Launches the command, waits for completion, and returns its exit code and captured output.

## See Also

* [`ProcessInterface`](ProcessInterface.md) — for advanced execution control.
* [`CommandResult`](CommandResult.md) — output structure returned by `runSync()`.

*This document was last updated for SwiftSlash v4.0.0*