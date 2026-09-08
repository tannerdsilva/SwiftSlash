# BYO Data Channels — design plan

status: proposal — pending review
branch: `feat/byo-data-channels`
scope: public API of the `SwiftSlash` product only. no new dependencies. no new targets.

## 1. The feature in one paragraph

Allow a caller to hand SwiftSlash a **file descriptor it already owns** and have that
descriptor bound to a child process file handle at spawn, while SwiftSlash stays entirely
out of the data path for that descriptor: no pipe creation, no event-trigger registration,
no reads, no writes, no flag mutation, no closing. This is the "bring your own" transport
seam that lets a caller run a SwiftNIO (or any other) data pipeline against a child process
without SwiftSlash taking any dependency — because everything interoperates at the level of
raw POSIX file descriptors, the one interface every IO library already speaks.

Reaping (`waitpid`), task cancellation (process group signal), state transitions, and
`signal(_:)` are untouched. A configuration that is *all* BYO still reaps and cancels
exactly like the built-in pipeline.

## 2. Why the file descriptor is the correct seam

The only thing a child process actually needs from its parent is **its file descriptors**.
Everything else in the current pipeline — `PosixPipe`, the `EventTrigger` registrations, the
read/write tasks, the `LineParser`, the write futures — exists to service SwiftSlash-owned
pipes once they exist. `ProcessLogistics.spawn` already builds the `dup2` operations that are
applied by `posix_spawn`; the BYO feature is simply: let the **source** of a `dup2` pair be a
caller-provided descriptor instead of a SwiftSlash-created pipe end.

The current state machines confirm this:

| pipeline piece | what it does | needed for a BYO channel? |
|---|---|---|
| `PosixPipe(forChild*ing)` | allocates a pipe, marks CLOEXEC | no — caller brings it |
| `EventTrigger.register(reader/writer:)` | yields readiness events into a FIFO, completes a finish future on EOF | no — caller owns observation of its own fd |
| `WriteTask` / `ReadTask` | drains/feeds SwiftSlash-owned pipe ends | no — zero tasks are produced |
| `dup2Ops -> posix_spawn` | binds the fd to the child fh | **yes — the one load-bearing step** |
| `waitpid` reaping, `kill(-pid)` on cancel | lifecycle | yes — untouched, channel-agnostic |

## 3. Public API change (the entire external surface)

### 3.1 new public type

```swift
/// a file descriptor owned by the caller, handed to SwiftSlash for binding to a child
/// process file handle. swiftslash never closes, mutates, registers, reads, or writes
/// this descriptor; the caller retains ownership for the whole child lifecycle.
public struct FileDescriptor:Sendable, Hashable {
    /// the raw system file descriptor integer.
    public let rawValue:Int32
    /// wraps a raw system file descriptor value.
    public init(rawValue:Int32)
}
```

Typed handle (not a bare `Int32`) — consistent with the house rule against raw-id APIs.

### 3.2 two new enum cases — one per child-side direction

```swift
public enum ChildWrite:Sendable {
    case toParentProcess(stream:ParentRead, separator:[UInt8])
    case toNull
    case byo(fd:FileDescriptor)   // NEW — caller owns all parent-side reading
}

public enum ChildRead:Sendable {
    case fromParentProcess(stream:ParentWrite)
    case fromNull
    case byo(fd:FileDescriptor)   // NEW — caller owns all parent-side writing
}
```

Semantics:

- `DataChannel.write(.byo(fd: f))` — `f` is `dup2`'d onto the child's target file handle;
  the child **writes** to it (the descriptor the caller hands over is the *child-facing* end).
  The caller keeps the opposite end and reads it (e.g. via a NIO `FileChannel`).
- `DataChannel.read(.byo(fd: f))` — `f` is `dup2`'d onto the child's target file handle;
  the child **reads** from it. The caller keeps the opposite end and writes to it.

The `.write` / `.read` position is preserved (it still describes the *child's* direction),
so `ChildProcess[channel:fh]`, `[writer:fh]`, `[reader:fh]` keep working unchanged and the
`.byo` configuration is reachable by pattern match. The `stdin` / `stdout` / `stderr`
convenience accessors correctly continue to `fatalError` on a BYO configuration (they
require the built-in stream types) — documented, unchanged behavior.

Works for any fd-like object — pipes today, `socketpair`, a PTY slave, a regular file
dup'd into the child. `dup2` does not care.

No new protocol. A `DataChannelTransport`-style protocol was considered and rejected: every
conceivable transport reduces to "here is one `Int32`", a protocol with a single
conformance that exists only to carry an integer is exactly the abstraction the design
ordering warns about. The POSIX file descriptor *is* the universal transport interface;
SwiftNIO's own `NIOFileHandle` attaches to the same integer.

### 3.3 the ownership contract (the load-bearing invariant)

For a BYO descriptor, SwiftSlash guarantees:

1. **never closes it** — on success, on launch failure, on cancellation, on reap;
2. **never mutates it** — no `FD_CLOEXEC`, no `O_NONBLOCK`, nothing;
3. **never registers it** with the `EventTrigger` (see §6);
4. **never reads or writes it**;
5. **is indifferent to when the caller closes it** after spawn (the child holds its own
   `dup2`'d copy; early close only affects the caller's own IO, which is theirs).

The caller owes SwiftSlash exactly one thing: **the descriptor must be valid and open for
the duration of the `spawn`** (from `ChildProcess` construction through the `posix_spawn`
file-actions phase inside `run()`). This is enforced with a pre-flight check (§4.2) so a
violation surfaces as a named error, not as a confusing `errno` translation.

## 4. Internal change — surgical, fully contained in `ProcessLogistics`

### 4.1 `launch(package:)` — collect byo bindings; everything else untouched

The launch loop gains two exhaustive-switch arms (the only exhaustive switches over the
channel enums in the package — verified). They only record a binding; no pipe, no
registration, no task is produced:

```swift
// inside launch(package:), alongside the existing processPipes building
var byoFdBindings:[Int32:Int32] = [:]          // child fh -> caller fd

// in the .read(.byo(let fd)) arm and the .write(.byo(let fd)) arm:
byoFdBindings[fh] = fd.rawValue
```

`byoFdBindings` is passed to `spawn`. Keeping BYO bindings in a **separate** dictionary from
`processPipes` makes it structurally impossible for the existing cleanup paths (which close
pipe ends on launch failure and after spawn) to ever touch a caller-owned descriptor — the
"never close" guarantee is enforced by absence, not by a conditional.

`LaunchPackage` needs no new fields: it already carries `dataChannels`, which is precisely
where the BYO configuration lives.

### 4.2 `spawn` — append byo dup2 ops; unchanged posix_spawn path

```swift
var dup2Ops:[Int32] = []
for (targetFH, pipe) in pipes { /* existing arms unchanged */ }
for (targetFH, callerFD) in byoFdBindings {
    dup2Ops.append(contentsOf:[callerFD, targetFH])
}
```

The `__cswiftslash_posix_spawn` C helper is already correct for this input (plain
`posix_spawn_file_actions_adddup2`; async-signal-safe; works on macOS kqueue-less spawn and
glibc/musl CLONE_VM children). **No C changes.**

New named errors and hardening for the pre-flight check, all inside `launch()` before any pipe or
process work happens:

- `invalidByoFileDescriptor` (new `SpawnError` case) — `dup(2)` of the caller descriptor fails
  (closed or negative descriptor).
- `byoFileDescriptorWrongDirection` (new `SpawnError` case) — `F_GETFL`/`O_ACCMODE` does not
  match the channel direction, catching swapped pipe ends before the child sees the descriptor.
- **Private-copy hardening**: the `dup(2)` taken at validation time is used as the `dup2` source,
  not the caller's descriptor. the copy is released when the launch settles, which closes the
  validation-to-spawn TOCTOU window entirely (a caller closing their descriptor after validation,
  or a reused number, can no longer affect the spawn or cross-wire another open file description
  into the child).
- defensively, `posix_spawn` returning `EBADF` (a dup2 source not open at spawn time) now maps
  to `invalidByoFileDescriptor` instead of `.internalFailure`.

### 4.3 `run()` / `ChildProcess` — zero changes

For a pure-BYO configuration `writeTasks` and `readTasks` are empty, `tg.waitForAll()`
returns immediately, `waitpid` blocks until exit, cancellation and reaping proceed
identically. The only developer-facing obligation is documented: the caller must drive its
own IO (its NIO event loop) while `run()` awaits — that is the definition of BYO.

### 4.4 event-driven reaping — post-review revision (original refinement withdrawn)

The originally proposed "optional micro-refinement" (lazy event-trigger instantiation so a
pure-BYO config never spawns a pthread) is **withdrawn**. An adversarial review found that
cooperative-poll reaping (`waitpid(WNOHANG)` + `try? await Task.sleep`) busy-spins at ~5M
iterations/sec once the calling task is cancelled, because `Task.sleep` throws on a cancelled
task *without suspending* — the byo cancellation test passed only because `/bin/sleep` died in
milliseconds, and a child that ignores SIGTERM would burn a whole core and starve the actor.

Reaping is now **event-driven** through the event trigger:

- macOS: the pid is registered as `EVFILT_PROC`/`NOTE_EXIT` on the trigger's kqueue.
- Linux: a `pidfd_open` descriptor is registered for `EPOLLIN` on the trigger's epoll (a
  cooperative poll loop remains as a fallback for kernels older than 5.3).
- `waitPIDAsync` registers the process, then suspends on the monitor FIFO with a
  **cancellation-immune** consumer (`.noAction`), so a cancelled task genuinely suspends until
  the child exits — zero CPU, no actor blocking, no polling latency.
- consequence: the event trigger is required for every launch (reaping needs it), so it is
  created unconditionally again. one shared process-lifetime pthread; the "no hidden pthread"
  property was not worth trading for reaping correctness.

## 5. Feature parity — nothing regresses

| SwiftSlash behavior | built-in pipeline | all-BYO configuration |
|---|---|---|
| `run()` / `run(cancellationSignal:)` reaps with `waitpid`, returns `Exit` | yes | **yes, identical** |
| `state` lifecycle (`initialized → launching → running → reaped`) | yes | yes, identical |
| cancellation signals the whole process group, then throws `CancellationError` | yes | **yes, identical** |
| `signal(_:)` | yes | yes |
| stdout/stderr line-split `AsyncSequence` | yes | provided by the caller's transport (NIO) |
| stdin write-with-flush-future | yes | provided by the caller's transport (NIO) |
| independent unbounded event loop for stdio | built-in | caller's event loop (the point of BYO) |
| mixed configurations (built-in + BYO on different fhs) | — | supported; each fh is routed independently |

Reaping is not merely "unaffected", it is *structurally* unaffected: reaping was never tied
to the data channels — it is one `waitpid` after the task group drains, and a BYO config
simply has nothing to drain.

## 6. Your EventTrigger closure-monitoring speculation — verdict

Short version: **don't.** It is technically possible but it is the wrong tool, and your
instinct about *why* it would be safe is slightly off in a useful way.

The correction first: the danger was never "SwiftSlash reading the data" — kqueue and
epoll never consume a byte, and multiple pollers (SwiftSlash's trigger + NIO's event loop)
can legally watch the same descriptor. The real problems are the FIFO and the lifecycle:

1. **The existing registration kinds would corrupt themselves.** `register(reader:)` yields
   a readiness signal into a data FIFO on *every* readable event (Linux even issues
   `FIONREAD` and forwards the byte count). A BYO descriptor that is receiving data has no
   consumer for those signals — the FIFO is unbounded (`try! FIFO()`) and would grow
   without limit for the life of the channel. To monitor without reading you could not
   reuse the existing API "as it already does"; you would have to add a *new* registration
   kind ("signal EOF only; ignore data events") to `Register` and implement distinct
   filter handling in both the kqueue and epoll backends.
2. **It buys nothing.** The built-in EOF→finishFuture path exists for exactly one reason:
   to terminate SwiftSlash's *own* read/write tasks so they can drop their registrations and
   close SwiftSlash-owned fds. A BYO channel has no SwiftSlash task, no SwiftSlash-owned fd,
   and no registration to tear down. The caller already learns of child-side close in the
   place that matters most: their own read returns 0 / their NIO channel goes inactive, on
   the same thread that owns the bytes.
3. **It leaks a lifecycle.** Owners of a monitor registration would be two parties who cannot
   coordinate: SwiftSlash doesn't know when the caller is done with the fd, and the caller
   doesn't know SwiftSlash's `EventTrigger` exists. Deregistration would have to be hooked
   to process exit (a cross-cutting change in `run()`), and the EOF future would be a second
   source of truth racing the caller's own channel state.
4. **Double the platform surface to test.** kqueue reports EOF (`EV_EOF` + pending `data`)
   differently from epoll (`EPOLLRDHUP` vs `EPOLLHUP`); both new behaviors would need their
   own coverage on both platforms.

The `EventTrigger` is also the wrong home for this by construction: it lives in the
`SwiftSlashEventTrigger` target, which is **not** a product of this package — callers cannot
see it, so any monitoring API added there would be invisible to the very user who would
need it.

Net: the BYO data seam is *invisible to the event trigger by design*. The event trigger *is*
used for one lifecycle task — watching the child process itself exit, to drive `run()`'s
reap (§4.4) — but never for the contents of a BYO descriptor.

## 7. Test plan (Swift Testing, one file per suite)

New suite `Tests/SwiftSlashInternalTests/SwiftSlash/BYODataChannelTests.swift`, serialized,
tagged, mirroring the existing process-test conventions. Tests use `PosixPipe`
(`@testable`-visible through the already-imported `SwiftSlashFHHelpers`) to fabricate
caller-owned pipes and hand SwiftSlash the child-facing end.

1. **`testByoStdout`** — the child generates a payload far larger than any platform pipe
   capacity (`yes marker | head -c 200000`); stdout = `.write(.byo(fd: writing end))`; the test
   reads the *caller's* retained read end raw; asserts byte-exact equality with **no** line
   splitting or mangling (proves SwiftSlash is not in the data path, even under backpressure)
   and `exit == .code(0)`.
2. **`testByoStdin`** — child `cat`; stdin = `.read(.byo(fd: reading end))`; the test writes
   a known payload to its retained write end, closes it, asserts the child exits cleanly
   having seen EOF.
3. **`testByoMixed`** — stdout built-in (assert the line `AsyncSequence` still works),
   stderr BYO (assert raw bytes): built-in and BYO channels compose on one process.
4. **`testByoOwnership`** — *the* ownership test: after `run()` returns, both caller fds are
   still valid (`__cswiftslash_fcntl_getfd` ≥ 0 for each) — SwiftSlash never closed them —
   and `exit == .code(0)`. Run once with an all-BYO configuration.
5. **`testByoCancellation`** — child sleeps; all-BYO; `run(cancellationSignal:SIGTERM)`;
   cancel mid-flight; assert `CancellationError` is thrown and `state == .reaped` (mirrors
   `CancellationTests`, proves cancellation is channel-agnostic).
6. **`testByoStubbornCancellation`** — regression test for the reaping fix: the child
   ignores SIGTERM (`trap '' TERM`) and loops forever; after cancellation the actor must
   stay responsive (state reads return `.running`, `signal(SIGKILL)` interleaves) and the
   process must be reaped. this test structurally fails under the pre-review polling reap.
7. **`testByoWrongDirection`** — a read-only descriptor on a child-writing channel (and its
   mirror: a write-only descriptor on a child-reading channel) throws
   `byoFileDescriptorWrongDirection` before spawn.
8. **`testByoInvalidDescriptor`** — a closed descriptor (or `rawValue:-1`) in the channel
   map throws the dedicated `SpawnError` case before any process is spawned.
9. **`testFileDescriptorType`** — `rawValue` round-trip; `Hashable`.

No changes to existing suites. `swift test` on macOS is the gate (baseline green at commit
time); Linux CI would run the identical suite (the pidfd path is exercised on Linux).

## 8. Documentation

- Inline docc on `FileDescriptor` and both `.byo` cases (§3.2 ownership contract, child-facing
  end semantics).
- New extended article `Sources/SwiftSlash/SwiftSlash.docc/Bring Your Own Data Channels.md`:
  the contract, a pipe example, a PTY/socketpair note, the mixed-configuration example, and
  a dependency-free SwiftNIO interop sketch (`NIOFileHandle(descriptor:takeOwnership:false)`
  style — illustrative only, no import).
- Topic pages: add the new case references to `ChildWrite.md` and `ChildRead.md`; link the
  BYO article from `ChildProcess.md` and `DataChannel.md`.
- Note on `ChildProcess` fh-keyed docs: BYO configurations are reachable via
  `[channel:fh]` / `[writer:fh]` / `[reader:fh]` pattern matching; convenience accessors
  (`stdin`/`stdout`/`stderr`) remain built-in-only.
- README: one-line mention plus link to the article.

## 9. Versioning & compatibility

Purely additive public API (two enum cases, one new type). No existing declaration is
changed or removed. The exhaustive switches that must grow (the `launch` loop) are `internal`,
and every *public* switch over these enums already uses `default:`. Non-breaking → next minor
release (this branch already carries post-4.0.6 work; the BYO change releases with that
version as a minor bump). DocC must generate warning-free. Held to the pre-release bar:
squashable warnings gone, no `fatalError` in new code, docs match the shipped API.

## 10. Explicitly out of scope

- IN: caller-owned descriptors bound to child fhs.
- OUT: SwiftSlash creating a pipe and *returning* the parent end to the caller (that is the
  built-in pipeline with an fd-shaped leak; not BYO, and it drags the event trigger back in).
- OUT: any new event-trigger API or monitoring mode (§6).
- OUT: any change to `Command.runSync` / `SyncResult` (built-in convenience, unchanged).
- OUT: protocol abstraction over the fd seam (§3.2).

## 11. Open decisions for review

1. Case name: `.byo(fd:)` (matches the feature vocabulary) vs the more formal
   `.external(fd:)` / `.provided(fd:)`. Default: `.byo`.
2. Include the §4.4 lazy-event-trigger refinement in the same change, or land it as a
   separate follow-up.
3. Pre-flight check (§4.2) as a dedicated `SpawnError` case — recommended; alternatively let
   posix_spawn surface `EBADF` (mapped today to `.internalFailure`).
