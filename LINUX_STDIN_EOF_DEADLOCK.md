# Linux stdin-EOF deadlock in SwiftSlash's EventTrigger

> **Affected versions:** 4.0.5 and 5.0.0 — both verified. The registration code is
> unchanged across the 4.x/5.x line, so every release since the Linux event trigger
> was introduced is presumed affected.
> **Platform:** Linux only. macOS does not exhibit the bug.
> **Severity:** functional deadlock — any consumer that pipes data into a child and
> expects the child to see EOF on stdin hangs indefinitely.

## Summary

`ChildProcess` (and therefore `Command`/`runSync` on the parent side) cannot deliver a
closing EOF on a child's stdin on Linux. The stdin *payload* is written, but the
child's stdin file descriptor is never closed by the parent, so any child that blocks
reading stdin until EOF (`cat`, `sort`, `wg pubkey`, `md5sum`, SSH keymgmt, …) waits
forever, and `ChildProcess.run()` never returns.

The failure is independent of call-site ordering: every order of `yield()`,
`closeDataChannel()`, and `run()` deadlocks against an EOF-consuming child on Linux
(verified, see [Reproduction](#reproduction)).

The root cause is the edge-triggered (`EPOLLET`) registration of the stdin *writer*
file descriptor together with a write-task loop whose EOF handling is only reachable
on a subsequent event — an event that edge-triggered epoll can never deliver for a
pipe that is (and remains) writable.

## Report origin

Wiremand — the Linux WireGuard management daemon — hit this while deriving a client
public key via `wg pubkey` (which reads its 44-byte private key from stdin and blocks
until EOF). The child hung in a live functional test; the parent sat in `sigsuspend`
with the child `wg pubkey` process alive and no EPOLLOUT delivery in progress.

## Affected public surface

- `ChildProcess(cmd).stdin` — `DataChannel.ChildRead.ParentWrite`
  (`yield(_:)`, `write(_:)`, `closeDataChannel()`)
- `Command.runSync()` when the child must consume stdin to EOF
- Everything built on the above (BYO consumers in v5 included)

## Reproduction

A child that reads **all of stdin until EOF** is the trigger. Minimal Swift snippet:

```swift
import SwiftSlash

let proc = ChildProcess(Command(absolutePath: "/bin/cat", arguments: []))
try proc.stdin.yield([UInt8]("hello\n".utf8))
proc.stdin.closeDataChannel()
let exit = try await proc.run()   // never returns on Linux; the fd is never closed
```

Four call-site orderings were exercised against two EOF-consuming children
(`/bin/cat`, `/usr/bin/wg pubkey`) on Ubuntu 24.04 (kernel 6.8.0-137-generic),
Swift 6.3.3, SwiftSlash 4.0.5:

| Pattern | cat | wg pubkey |
|---|---|---|
| A: `yield()` + `closeDataChannel()` before `run()` | 🔴 deadlock (rc 124) | 🔴 deadlock (rc 124) |
| B: `async let run()`; `yield()` after; no close | 🔴 deadlock | 🔴 deadlock |
| C: `yield()` before `run()`; no close | 🔴 deadlock | 🔴 deadlock |
| D: `async let run()`; `yield()` + `closeDataChannel()` after | 🔴 deadlock | 🔴 deadlock |

All four timed out (coreutils `timeout 6`, exit 124). On macOS the same code against
`/bin/cat` completes with exit 0 and the echoed payload.

## Root cause

### 1. The stdin writer fd is registered edge-triggered

`Sources/SwiftSlashEventTrigger/Platforms/LinuxEventTrigger.swift:234–242`:

```swift
@SwiftSlashGlobalSerialization internal static func register(_ ev:EventTriggerHandlePrimitive, writer:Int32) throws(EventTriggerErrors) {
	var newEvent = epoll_event()
	newEvent.data.fd = writer
	newEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue) | UInt32(EPOLLET.rawValue)
	guard epoll_ctl(ev, EPOLL_CTL_ADD, writer, &newEvent) == 0 else {
		throw EventTriggerErrors.writerRegistrationFailure(writer, __cswiftslash_get_errno())
	}
}
```

The reader registration (same file, line 229) is also `EPOLLET`, but reads are
unaffected: a child writing output is a *transition* on the read end, so edge events
fire naturally. Writes are the broken direction.

### 2. Edge-triggered epoll is one-shot for an always-writable pipe

`EPOLLET` delivers an event only on a **state transition**. A fresh pipe whose write
end is empty is permanently *ready for writing*. `epoll_ctl(EPOLL_CTL_ADD)` on an
already-ready fd reports readiness **once**, then never again while the fd stays
writable — there is no unready→ready transition to detect.

Verified directly against the kernel:

```text
EPOLLOUT|EPOLLET on empty pipe (initial readiness): events=[(4, 4)]
EPOLLOUT|EPOLLET second poll:                          []          # one-shot, never re-fires
EPOLLOUT (level) first poll:                           [(4, 4)]
EPOLLOUT (level) second poll:                          [(4, 4)]     # re-fires while writable
```

### 3. The write task can only act on a signal, and the EOF path needs a second one

`Sources/SwiftSlash/Logistics.swift:175–245` — the stdin write task drains the user
data FIFO only inside an event wake:

```swift
taskGroup.addTask { [writeConsumer = writeConsumerFIFO.makeAsyncConsumerExplicit(), et = eventTrigger] in
	defer {
		try! et.deregister(writer:wFH)
		try! wFH.closeFileHandle()          // ← the only place EOF is produced
	}
	...
	systemEventLoopInfinite: repeat {
		switch await writeConsumer.next(whenTaskCancelled:.noAction) {   // ← block until EPOLLOUT signal
			case .element(_):
				...
				currentWriteStepper = await getNextWriteStep(iterator:userDataConsume)
				guard currentWriteStepper != nil else { break systemEventLoopInfinite }  // .capped ⇒ done
				...
			case .capped(_): break systemEventLoopInfinite
			...
		}
	} while true
	...
}
```

The sequence on Linux:

1. `epoll_ctl(ADD, … EPOLLET)` → the single initial writability event fires.
2. Write task wakes, `getNextWriteStep` pulls the one queued payload, flushes it to
   the child. Data delivery works — this is why the shipped piped-input tests pass.
3. Write task returns to `writeConsumer.next()` waiting for the **next** signal.
4. No next signal ever arrives (edge-triggered one-shot, pipe stays writable — step 2).
5. `closeDataChannel()` (`Sources/SwiftSlash/DataChannel.swift:161`) only marks the
   user-data FIFO finished. The `.capped` branch that would `break` the loop and
   reach the `defer` (deregister + close the child's stdin fd) is only evaluated
   **on a subsequent wake** — which never comes. EOF is structurally unreachable.

### 4. Why macOS is immune

`Sources/SwiftSlashEventTrigger/Platforms/MacOSETImpl.swift:244–245` registers the
writer with:

```swift
newEvent.flags = UInt16(EV_ADD | EV_CLEAR | EV_EOF)
newEvent.filter = Int16(EVFILT_WRITE)
```

kqueue `EVFILT_WRITE` is level-triggered: it is reported while the fd is writable and
re-issued after `EV_CLEAR` clears it, so the write task *does* receive the second
signal, sees the finished FIFO, breaks, and closes the child's stdin. The same
consumer code works on macOS end to end — which is why a macOS-run test suite never
observes the bug.

### 5. Why the shipped unit tests do not catch it

`Tests/SwiftSlashInternalTests/SwiftSlash/SwiftSlashProcessTests.swift`:

- `:141` — `sh -c 'IFS= read num && exit "$num"'` (exit-code-0-255 sweep)
- `:170` — `sh -c 'IFS= read line && printf "%s\n" "$line"; exit 0'`

Both children **exit after consuming a single line** — they never wait for EOF, so
the missing EOF is irrelevant to them. Neither test calls `closeDataChannel()` in a
way that requires EOF propagation. The full suite passes 47/47 on Linux (verified),
which is consistent: the *data* path works; only *EOF* delivery is broken.

## Proposed fixes

### Option A — level-triggered writers (smallest change, recommended)

Drop `EPOLLET` for the writer registration (leave it for readers):

```swift
newEvent.events = UInt32(EPOLLOUT.rawValue) | UInt32(EPOLLERR.rawValue) | UInt32(EPOLLHUP.rawValue)
```

Level-triggered `EPOLLOUT` re-fires while the pipe is writable, so the write task
receives the second wake, hits the `.capped` branch, and reaches the
`defer { …closeFileHandle() }`. No busy-loop: the loop terminates by breaking at the
first `.capped` and then deregisters + closes the fd.

### Option B — re-arm the writer after each consumed event

Keep edge semantics for the signal *rate*, but explicitly re-arm the writer after each
consumed event (re-`epoll_ctl(MOD)` with `EPOLLET`, or use `EPOLLONESHOT` + re-arm),
so the post-flush wake that observes `.capped` is guaranteed. More moving parts than A.

### Option C — handle EOF at the source

When `closeDataChannel()` runs with no pending writes, have it make the event loop
observable of the finish *synchronously* (e.g. wake the trigger via the cancel pipe so
the pending `.capped` drain happens immediately, rather than waiting for a pipe event
that can never arrive). Preserves edge semantics but touches the channel/trigger
boundary.

Any fix must guarantee the invariant: **once the user data FIFO is finished, the
write fd is closed even in the absence of any further fd readiness event.**

## Regression test (fails on Linux today)

Add to `SwiftSlashProcessTests`:

```swift
@Test("SwiftSlashProcessTests :: stdin EOF is delivered to an EOF-consuming child",
      .timeLimit(.minutes(1)))
func stdinEOFDelivery() async throws {
	// child consumes all of stdin to EOF, then confirms it saw EOF.
	let command = Command(absolutePath: "/bin/sh", arguments: ["-c", #"cat > /dev/null && echo "EOF_OK""#])
	let process = ChildProcess(command)
	let exit = try await process.run()
	#expect(exit == .code(0))
	// additionally assert stdout contains "EOF_OK"
}
```

A child that must observe EOF to terminate (`cat > /dev/null`, `wg pubkey`, `sort`)
is the defining case the existing tests miss. Any fix targeting the writer path must
make this test pass on Linux.

## Environment / evidence provenance

- **Host:** 45.79.19.118 — Ubuntu 24.04 (`libnftables-dev 1.0.9`), x86_64, Swift 6.3.3
  (swiftly toolchain), SwiftSlash checked out at tags `4.0.5` and `5.0.0`(`aa77ca6`).
- `swift test` on 4.0.5: 47/47 suites pass in ~44 s, Linux.
- Pattern matrix: parametric `ChildProcess` driver invoking the four orderings × two
  children, wrapped in `timeout 6`; rc 124 = deadlock.
- Kernel check: python `select.epoll()` demonstrating EPOLLET one-shot vs level
  re-firing, against fresh `os.pipe()` fds.
- Downstream workaround (wiremand): feed the child's stdin from a `mkstemp` file via
  a single `sh -c "cat '<path>' | wg pubkey"` — the path is generated internally,
  quoted, and contains no shell metacharacters, so the shelled invocation carries no
  injection surface and key material never appears in argv. The mechanism is
  documented in the code comment at `WireguardExecute.generateClient`.
- Memory/notes: the EventTrigger engine, `WriteStepper`, and the write-task loop are
  structurally identical between 4.0.5 and 5.0.0 at the affected sites; only the
  process/channel *front-ends* changed in 5.0.0 (BYO data channels).

## Status

- [x] Fix applied — not Option A/B/C as originally sketched; see [Fix applied](#fix-applied-2026-09-12)
- [x] v5 verified against the fix (66/66 tests, macOS + Linux)
- [ ] CHANGELOG entry — `n/a`: this repository has no CHANGELOG file; release notes are published as git tags.

## Fix applied (2026-09-12)

The fix is **not** any of the three originally-proposed options; empirical
investigation changed the calculus. Two probes settled the open questions:

1. **kqueue `EV_CLEAR` is NOT level-triggered.** A direct kernel probe on macOS
   shows `EVFILT_WRITE | EV_CLEAR` fires once for an initially-writable pipe and
   does *not* re-fire while it stays writable (second poll = no event). What
   actually happens: **each successful `write()` re-arms the filter** (a tiny
   16-byte write produced a fresh event). macOS "just works" because every data
   flush is itself an event that lets the loop observe the finished FIFO —
   there is no level-triggered re-firing to copy. Option A as literally stated
   ("match macOS") would therefore have *diverged* from macOS's real behavior
   and, worse, level-triggered `EPOLLOUT` on a permanently-writable pipe keeps
   `epoll_wait` returning immediately — a busy-spin on the event-trigger thread
   whenever any write channel is idle (this repo explicitly values CPU
   efficiency). Option A was rejected on those grounds.

2. **The write task is woken by nothing but pipe signals.** `closeDataChannel()`
   only caps the user-data FIFO; the loop evaluatees that cap only after a
   *writability* signal, and on Linux edge-triggered epoll never delivers a
   second one. Worse, the same mechanism silently breaks *multi-chunk*
   streaming on Linux: after the initial event flushes chunk 1, a chunk 2
   yielded later sits in the user FIFO forever because the task is parked on the
   signal FIFO, not the data FIFO.

### The fix (data-driven write loop)

`Sources/SwiftSlash/Logistics.swift` — the stdin write task is rewritten to be
driven by the **user data stream** instead of by pipe readiness signals:

- an element means "write these bytes to the child";
- a cap means "channel finished — close the write descriptor" (the EOF);
- pushing data or closing the channel resumes the consumer directly, so when
  the loop is parked on the user stream with no bytes in flight, the finish is
  observed **without any further pipe-readiness event** — the exact situation
  that deadlocked on Linux. when a chunk is mid-flight in a full pipe, EOF is
  delivered only after that chunk drains (a full→space transition that
  edge-triggered epoll reports, and that any child reading to EOF will
  produce); closing earlier would truncate the child's input, so deferring EOF
  until the in-flight bytes flush is the correct ordering;
- the writability signal consumer is consulted only when a write is refused
  because the pipe is full.

Enabling changes:

- `Sources/SwiftSlashFHHelpers/FHHelpers.swift` — `writeFH` now surfaces a full
  non-blocking pipe as `FileHandleError.error_wouldblock` (previously it
  busy-retried `EAGAIN` forever — a latent 100%-CPU spin), and maps `EPIPE` to
  the previously-dead `FileHandleError.error_pipe` case.
- SIGPIPE suppression — a data-driven writer can legitimately issue a write
  near a child's exit; with the default disposition that race kills the parent
  with SIGPIPE (verified: a Swift runtime-mode process dies, exit 141). The
  first launch installs `signal(SIGPIPE, SIG_IGN)` once
  (`__cswiftslash_ignore_sigpipe`), turning the race into a recoverable EPIPE
  (also verified: with `SIG_IGN`, the write returns `-1`/`EPIPE`). This is a
  **process-wide disposition change**, the standard approach for pipe/socket
  I/O (no per-descriptor SIGPIPE suppression exists for pipes on either
  platform); it is installed exactly once per process and can never be
  uninstalled. Children are unaffected: the spawn helper already resets every
  disposition to default via `POSIX_SPAWN_SETSIGDEF` (verified necessary —
  POSIX preserves *ignored* dispositions across `exec`, so without it children
  would inherit the ignore on glibc/musl/macOS).

A correctness note about the old code's SIGPIPE safety: the report's original
reasoning ("a dead pipe never delivers EPOLLOUT") is kernel-inaccurate — a
non-full pipe whose read end is gone is still `EPOLLOUT`-ready, and read-end
closure is an `EPOLLERR` 0→1 edge (pipes never report `EPOLLHUP` on the write
end). The old loop happened to be SIGPIPE-safe for a different reason: on child
death the dispatcher runs the `EPOLLERR` branch, which completes the
termination future *without* yielding a writability signal, so the task broke
out of its loop instead of writing again. There was nonetheless a real, narrow
SIGPIPE race in the old code: the single initial `EPOLLOUT` event can sit
buffered in the max-1 signal FIFO, and finish-with-buffered ordering delivers
that stale *element* first — the old loop then wrote after the child's death.
The suppression in this fix closes that latent crash too.

### Regression tests (all pass on macOS + Linux)

The originally sketched regression test was wrong as written — it never closes
the channel, so it deadlocks on *both* platforms. The shipped tests:

- `stdinEOFDelivery` — `sh -c 'cat > /dev/null && echo "EOF_OK"'`, payload +
  `closeDataChannel()`, asserts exit 0 and `EOF_OK` on stdout.
- `multiChunkStreamingToEOF` — `/bin/cat`, three chunks yielded 300 ms apart,
  byte-exact round trip after `closeDataChannel()` (catches the silent
  multi-chunk starvation on Linux).
- `StdinStressTests` (new suite) — mid-stream child exit survival (SIGPIPE),
  once-only SIGPIPE suppression, and full→space backpressure through a
  136 KB payload with a slow-reading child.

### Environment note

- Verified on macOS (arm64e, Swift 6.x toolchain) and the original report host
  (45.79.19.118, Ubuntu 24.04, Swift 6.3.3): 66/66 tests, both platforms.
- `Command.runSync()` was listed as Linux-affected. Verified empirically that it
  hangs on **macOS too**: `runSync` never writes or closes stdin, so an
  EOF-consuming child waits forever on any platform. That is a separate,
  platform-independent design limitation of `runSync` (no stdin channel is
  exposed), not this bug.

### Residual risks (pre-existing, acknowledged, not changed)

These were surfaced by adversarial review of the fix; none are introduced by it
and none were changed, to keep the fix scoped to the problems this document
highlights:

- **Linux dispatcher `fatalError`s.** `LinuxEventTrigger.pthreadWork()` has
  `default: fatalError` guards for `EPOLLHUP`+writer and `EPOLLERR`+reader
  dispatch combinations. Against current kernels these are unreachable for
  pipe FDs (the write end reports `EPOLLOUT`/`EPOLLERR`, never `EPOLLHUP`; the
  read end reports `EPOLLIN`/`EPOLLHUP`, never `EPOLLERR`), and the full Linux
  suite passes, but a future kernel/FD-type change that surfaces one of those
  combinations would crash the event-trigger thread. Out of scope here; worth
  a follow-up hardening pass (`fatalError` → graceful no-op).
- **`readFH` busy-retries `EAGAIN`.** The symmetric helper still has
  `case EAGAIN: continue`, which on both platforms aliases `EWOULDBLOCK` (same
  value), making its `error_wouldblock` throw dead code and its full-pipe
  (read-side) spin latent. Unreachable in practice because reads are
  availability-bounded (`FIONREAD`); left unchanged to keep this fix on the
  write path.
