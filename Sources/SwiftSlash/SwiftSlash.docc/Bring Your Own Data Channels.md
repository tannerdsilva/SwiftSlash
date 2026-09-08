# Bring Your Own Data Channels

Seamlessly hand process I/O to your own transport — SwiftNIO, a socket, a PTY, or anything that accepts a POSIX file descriptor.

## Overview

SwiftSlash's built-in data channels manage every detail of the stdio pipeline for you: pipes are allocated, registers on the internal event trigger, bytes are read and split into lines, writes are paced and acknowledged. This is the right default for most callers.

But sometimes you want a different transport. If you are building on SwiftNIO, you already have an event loop and a buffering strategy; creating a **second**, competing pipeline inside SwiftSlash is wasteful and pulls the data through SwiftSlash's machinery for no benefit. "Bring your own" (BYO) data channels solve that: you hand SwiftSlash a file descriptor you already own, SwiftSlash binds it to the child process at spawn time — and then gets completely out of the way.

> SwiftSlash takes **no dependency** on SwiftNIO (or any other IO library) for this. The seam is the POSIX file descriptor itself, which every transport library already speaks.

## What SwiftSlash does — and does not — do with your descriptor

For a BYO channel, SwiftSlash's behavior is exactly this:

| | |
|---|---|
| **does** | duplicate (`dup2`) your descriptor onto the child's target file handle during `posix_spawn` |
| **never** | creates a pipe for the channel |
| **never** | registers the descriptor with its internal event trigger |
| **never** | reads from it or writes to it |
| **never** | mutates its flags (`O_NONBLOCK`, `FD_CLOEXEC`, …) |
| **never** | closes it — not on launch, not on cancellation, not on reap |

Every built-in guarantee that is not about the bytes themselves stays fully intact: the child is **reaped** with `waitpid`, task **cancellation** still signals the process group and throws `CancellationError`, `state` transitions normally, and `signal(_:)` works. A configuration that is entirely BYO behaves identically to a built-in configuration at the lifecycle level. Reaping never blocks your ability to observe `state` or deliver signals: the internal wait continually yields to the actor while the child runs.

## Ownership contract

- You pass the **child-facing** end of your descriptor pair — the end that the child should read from or write to at its file handle.
- You keep the **opposite** end and perform all data exchange on it (e.g. via a SwiftNIO `FileHandle`/`FileChannel`).
- The descriptor must be **valid and open for the duration of the spawn** — from the moment it is placed in the channel map until the child has launched. A closed or negative descriptor is rejected up front with ``SwiftSlash/ChildProcess/SpawnError/invalidByoFileDescriptor``.
- After the spawn, your copy of the child-facing descriptor is yours to close whenever you like. For a child-**writing** channel (stdout/stderr), note that the pipe only reports EOF to your reading end once *every* writer (including any copy you still hold) has closed it.
- SwiftSlash remains indifferent to when you close either end. Early closure only affects your own I/O, which is yours.

### Descriptor hygiene

Because SwiftSlash never mutates descriptor flags, any descriptor that is still open — and not marked `FD_CLOEXEC` — when the child is spawned is inherited by the child as a stray file descriptor, even when it is not named in a channel binding. In practice the important one is the retained, parent-facing end of a child-**writing** pipe: if that end leaks into the child, the child holds a writer reference and your reading end will not observe EOF while the child lives. Mark retained ends `FD_CLOEXEC` yourself (or close them after the spawn) if this matters to you.

## Using a pipe

```swift
import Foundation
import SwiftSlash

let pipe = Pipe()
let command = try Command("/bin/cat")

let child = ChildProcess(
    command,
    dataChannels: [
        STDIN_FILENO: .read(.byo(fd: .init(rawValue: pipe.fileHandleForReading.fileDescriptor))),
        STDOUT_FILENO: .write(.byo(fd: .init(rawValue: pipe.fileHandleForWriting.fileDescriptor))),
        STDERR_FILENO: .write(.byo(fd: .init(rawValue: pipe.fileHandleForWriting.fileDescriptor)))
    ]
)

async let exit = child.run()
// ... drive `pipe` however you like: plain reads, a background thread, or a transport.
```

Foundation's `Pipe` is used here for convenience — any descriptor works, including a `socketpair(2)` endpoint, a PTY slave, or a file descriptor obtained from another library.

## A SwiftNIO sketch (illustrative — no dependency)

BYO is designed for callers who already run a transport. The integration point is a raw `Int32`:

```swift
// your own pipe (Foundation, a socketpair, or your transport's allocator).
let pipe = try somePipeOfYourOwn()
let channel = ChildProcess(/* ... */, dataChannels: [ /* .byo(fd: …) for stdin/stdout/stderr */ ])

// hand the retained (parent-facing) ends to NIO without handing over ownership.
let stdinNIO   = NIOFileHandle(descriptor: pipe.writing, takeOwnership: false)
let stdoutNIO  = NIOFileHandle(descriptor: pipe.reading,  takeOwnership: false)
// ... run your NIO pipeline against those handles, then:
async let exit = channel.run()
```

Because SwiftSlash never owns or touches the descriptor, there is no ownership transfer to coordinate: `takeOwnership: false` is always the correct choice, and the descriptor's lifetime stays entirely in your hands.

## Mixing built-in and BYO channels

BYO applies per file handle. You can have a built-in, line-split `stdout` sequence and a BYO `stderr` in the same process, or vice versa:

```swift
dataChannels: [
    STDIN_FILENO: .read(.fromParentProcess(stream: .init())),
    STDOUT_FILENO: .write(.toParentProcess(stream: .init(), separator: [0x0A])),
    STDERR_FILENO: .write(.byo(fd: .init(rawValue: errPipe.fileHandleForWriting.fileDescriptor)))
]
```

Each file handle is routed independently. The convenience properties (`childProcess.stdin`, `stdout`, `stderr`) remain available only for the built-in stream configurations; a BYO channel is reached through ``SwiftSlash/ChildProcess/subscript(channel:)`` or the typed subscripts ``SwiftSlash/ChildProcess/subscript(writer:)`` / ``SwiftSlash/ChildProcess/subscript(reader:)``.

## Why not a separate event-trigger registration?

You might wonder whether SwiftSlash could also register your BYO descriptor with its internal event trigger — just to watch for the child closing its end. It is technically possible (multiple pollers may watch one descriptor, and neither kqueue nor epoll consumes data), but it is deliberately **not** done:

- The event trigger's existing reader/writer registrations yield readiness signals into data FIFOs; a BYO descriptor has no consumer for those signals, and the FIFOs are unbounded.
- The trigger's EOF notification exists to wind down *SwiftSlash's* I/O tasks. A BYO channel has none.
- You already observe EOF in the place that matters: your own read returns 0, or your NIO channel goes inactive.

Keep the BYO seam invisible to the event trigger — it is the simplest correct design, and it leaves your data path entirely under your control.
