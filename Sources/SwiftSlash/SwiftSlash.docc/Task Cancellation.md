# Cancelling a Running Command

SwiftSlash integrates directly with Swift's native task cancellation. When the task awaiting a process run is cancelled, the child process is terminated, its resources are released, and `CancellationError` is thrown to the caller.

## The Cancellable Run Paths

Both the convenient and the direct interfaces expose a cancellation-aware variant:

- ``SwiftSlash/Command/runSync(cancellationSignal:)`` — like ``SwiftSlash/Command/runSync()``, but responds to task cancellation.
- ``SwiftSlash/ChildProcess/run(cancellationSignal:)`` — like ``SwiftSlash/ChildProcess/run()``, but responds to task cancellation.

The plain ``SwiftSlash/Command/runSync()`` and ``SwiftSlash/ChildProcess/run()`` functions do not terminate the child process when the task is cancelled.

## What Happens on Cancellation

When the awaiting task is cancelled, the run performs the following sequence:

1. The configured signal is delivered to the child process and its entire process group.
2. The input/output streams wind down and have their cleanup completed.
3. The child process is reaped, guaranteeing no zombie processes or leaked file handles.
4. `CancellationError` is thrown to the caller.

If the task is cancelled before the process has been launched, no child process is ever created.

## Choosing a Signal

The default signal is ``SwiftSlash/ChildProcess/defaultCancellationSignal``, which is `SIGTERM`. It gives well-behaved processes a chance to perform cleanup before exiting, and it terminates the overwhelming majority of commands immediately.

If the child is known to ignore `SIGTERM`, or if no cleanup delay can be tolerated, pass `SIGKILL` explicitly. `SIGKILL` cannot be caught, blocked, or ignored, so termination is guaranteed.

## Process Group Semantics

Every child process is launched as the leader of its own process group. Cancellation signals the entire group rather than only the direct child. This is what allows orchestration shells — such as the ``SwiftSlash/Command/init(sh:environment:workingDirectory:)`` shell wrapper — to be shut down together with the commands they launched, since shells defer signals while waiting on a foreground child.

## Cancellation in Practice

```swift
let command = Command(absolutePath: "/usr/bin/du", arguments: ["-sh", "/"])

let task = Task {
    do {
        let result = try await command.runSync(cancellationSignal: ChildProcess.defaultCancellationSignal)
        print("Disk usage: \(String(bytes: result.stdout.first ?? [], encoding: .utf8) ?? "")")
    } catch is CancellationError {
        print("The command was cancelled; the child process has been terminated.")
    }
}

// some time later, abort the running command
task.cancel()
```
