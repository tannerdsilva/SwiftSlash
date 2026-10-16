# Cancelling a Running Command

SwiftSlash integrates directly with Swift's native task cancellation. When the task awaiting a process run is cancelled, the child process is terminated, its resources are released, and `CancellationError` is thrown to the caller.

## The Cancellable Run Paths

Both the convenient and the direct interfaces expose a cancellation-aware variant:

- ``SwiftSlash/Command/runSync(cancellationSignal:)`` — like ``SwiftSlash/Command/runSync()``, but responds to task cancellation.
- ``SwiftSlash/ChildProcess/run(cancellationSignal:)`` — like ``SwiftSlash/ChildProcess/run()``, but responds to task cancellation.

The plain ``SwiftSlash/Command/runSync()`` and ``SwiftSlash/ChildProcess/run()`` functions do not terminate the child process when the task is cancelled.

## What Happens on Cancellation

When the awaiting task is cancelled, the run performs the following sequence:

1. The configured signal is delivered to the child, and to its process group when the child's placement gives it one. See <doc:Process Groups and Detachment>.
2. The input/output streams wind down and have their cleanup completed.
3. The child process is reaped, guaranteeing no zombie processes or leaked file handles.
4. `CancellationError` is thrown to the caller.

If the task is cancelled before the process has been launched, no child process is ever created.

## Choosing a Signal

The default signal is ``SwiftSlash/ChildProcess/defaultCancellationSignal``, which is `SIGTERM`. It gives well-behaved processes a chance to perform cleanup before exiting, and it terminates the overwhelming majority of commands immediately.

If the child is known to ignore `SIGTERM`, or if no cleanup delay can be tolerated, pass `SIGKILL` explicitly. `SIGKILL` cannot be caught, blocked, or ignored, so termination is guaranteed.

Cancellation signals **once** and does not escalate. The launch never sends `SIGKILL` on its own initiative, because only the caller knows whether a cleanup delay is acceptable. Pass `SIGKILL` explicitly, or escalate a child that is stuck through ``SwiftSlash/ChildProcess/signal(_:to:)``.

## Process Group Semantics

Where the child sits is its **placement**, and the launch decides it rather than the command. A child placed ``SwiftSlash/ChildProcess/ProcessGroup/own`` — the default outside a launch — leads its own process group, so cancellation signals the entire group rather than only the direct child. This is what allows orchestration shells — such as the ``SwiftSlash/Command/init(sh:environment:workingDirectory:)`` shell wrapper — to be shut down together with the commands they launched, since shells defer signals while waiting on a foreground child.

A launch that is itself running inside another launch resolves ``SwiftSlash/ChildProcess/ProcessGroup/inherited`` instead: it joins the group it is already in, so the outermost teardown cascades through every level. A ``SwiftSlash/ChildProcess/ProcessGroup/detached`` child starts a new session and is deliberately unreachable.

Placements that do not lead a group are signalled by pid, because signalling a negated pid would address a group that does not exist and the signal would silently fail to arrive at all. The full table is in <doc:Process Groups and Detachment>.

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
