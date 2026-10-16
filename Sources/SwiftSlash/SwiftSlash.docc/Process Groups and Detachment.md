# Process Groups and Detachment

Every launch places its child in a process group, and that placement decides which signals reach the child — and whether it outlives the launch that created it.

## The Three Placements

| Placement | What the child gets | Reachable by the launch's teardown | Use it for |
| --- | --- | --- | --- |
| ``SwiftSlash/ChildProcess/ProcessGroup/own`` | A new process group (`pgid == pid`) | Yes — as a group, so the child's whole tree goes with it | The default outside a launch. Anything whose descendants must all be shut down together. |
| ``SwiftSlash/ChildProcess/ProcessGroup/inherited`` | Joins the launcher's process group | Only as a pid; the group belongs to whoever owns it | A launch running inside another launch, so an outer teardown cascades through it |
| ``SwiftSlash/ChildProcess/ProcessGroup/detached`` | A new session (`setsid(2)`), leading its own group and session | No — by design | Work that must outlive its launcher |

``SwiftSlash/ChildProcess/init(_:processGroup:dataChannels:)`` takes the placement. Omitting it resolves the default described below.

## Why Nesting Needed This

A child that itself spawns through SwiftSlash runs the same spawn path. When that path unconditionally requested a new group, a nested launch formed a *second* group that the outer `kill(-pgid)` could not reach: the grandchild was reparented and kept working after the caller had already reported failure. The caller cannot fix this on its own, because it cannot see grandchildren reliably.

So the spawner decides. Placement is part of the spawn contract rather than a spawn detail, and it is resolved at the single spawn site.

## Automatic Placement

A process nobody launched leads its own group — the historical behaviour, unchanged. A process that *was* launched joins the group of the launch it is already in, so an outer teardown cascades through every level. This is transitive: each generation resolves the same way, so a cascade is not merely moved one level deeper.

The resolution is neither configuration nor guesswork. A launch leaves a descriptor in its child, and the child reads it to learn where it sits. An explicit `processGroup:` argument always overrides the resolution.

To see what a running process was told, call ``SwiftSlash/CurrentEnvironment/launchIdentity()``: it reports the launching process, the caller's process group, and the caller's session, or `nil` outside a launch.

## The Reserved Descriptor

A launch writes a small record into a pipe and installs the read end in the child at **file descriptor 3**, before the child is created. The record carries a magic word, a protocol version, the placement the launcher applied, the launcher's pid, and the launcher's process group. The child reads it at first need and caches the answer: the read consumes the record, and a process's enclosing launch cannot change over its lifetime.

Consequences worth knowing:

- **Intermediaries pass it along.** The descriptor survives `exec` and is inherited by anything that does not close it, so a tool that is not itself a SwiftSlash program does not break the chain.
- **It is a one-shot record.** The write end is closed before the child starts, so the descriptor is "one record, then end of file".
- **Descriptor 3 is reserved.** The descriptor is installed there *after* every channel binding, so it takes the number for itself; a caller that binds a channel to descriptor 3 does not keep it. And a program that binds its own descriptor 3, or closes it, has no record to read. Placement then falls back to leading its own group — the historical behaviour. Nothing crashes, and nothing is guessed.
- **Reading it never blocks.** The child asks whether the descriptor is ready before it reads, so a program holding an *open* descriptor of its own there degrades exactly like one that closed it. A bare read would wait forever on a descriptor whose writer is still alive, which would hang the launch with no diagnostic at all.
- **The record is verified, not merely recognised.** The placement it names has to agree with where the process actually sits, so a stale or forged descriptor cannot talk a process into a placement it was never given.
- **A launch holds no descriptor for its lifetime.** Both ends are released before the launch returns, on every path, so the caller's descriptor table does not grow once per launch.

## Signals, and What a Launch Does Not Do

``SwiftSlash/ChildProcess/signal(_:to:)`` addresses either the child's pid (`.process`) or the child's whole group (`.processGroup`, the default), and the choice is observable rather than cosmetic. A multi-process tree that leads its own group is reachable only as a group; a pid-scoped signal is how a caller reaches a child *without* touching its descendants.

A shell defers signals while a foreground child runs, so a group signal is what shuts an `sh -c` orchestration down promptly.

Cancellation delivers its signal once. It does **not** escalate: if the child ignores ``SwiftSlash/ChildProcess/defaultCancellationSignal``, the launch does not send `SIGKILL` on its own initiative. Escalating is the caller's decision, expressed through ``SwiftSlash/ChildProcess/signal(_:to:)`` — pass `SIGKILL` where termination has to be guaranteed.

## Reaping

A zombie exists only where a parent has not reaped its own child, so placement changes *who dies*, never *who reaps*. The launch reaps its own child on every path: normal exit, non-zero exit, a launch that fails before it spawns anything, cancellation, and cancellation followed by an escalation. A descendant that the launch did not create is not the launch's child and is reaped by the system.

## The Limit

A child that calls `setsid(2)` or `setpgid(2)` itself escapes any process-group mechanism, as does a descendant that deliberately re-parents itself. The guarantee is **cooperative descendants**: everything that inherits, or is given, the group. Containment that survives an uncooperative descendant requires a container or a cgroup, not a process group.