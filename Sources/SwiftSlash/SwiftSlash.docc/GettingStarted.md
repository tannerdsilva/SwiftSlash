# Getting Started

Get started using SwiftSlash with the convenient interfaces of ``Command`` and ``Command/Result``.

## Define a Command

``Command`` defines the executable that SwiftSlash is going to run, as well as the parameters surrounding its execution (such as arguments, working directory and environment variables).

In this case, we will define a ``Command`` that lists every running process on our system.

```
let processStatusCommand = Command("ps aux") 
```

## Run a Command

The simplest way to run a ``Command`` is to use its convenience ``Command/runSync()`` function.

```
let processResult = try await processStatusCommand.runSync()
```

### Interpret Results of Execution

``Command/runSync()`` returns a ``Command/Result`` which contains the commands exit code and output data.

## Complete Example

```
let commandResult = try await Command("zfs --version").runSync()
if (commandResult.exitCode == 0) {
    let versionData = commandResult.stdout[0]
}
```
