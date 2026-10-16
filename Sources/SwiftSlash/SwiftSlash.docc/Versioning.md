# Project Versioning

SwiftSlash follows Semantic Versioning 2.0.0 to ensure clarity, predictability, and compatibility across releases.

## What is SemVer 2.0.0?

[Semantic Versioning (SemVer) 2.0.0](https://semver.org/spec/v2.0.0.html) is a scheme conveying meaning about a release through its version number in the format:

```
MAJOR.MINOR.PATCH
```

- **MAJOR**: incompatible API changes.
- **MINOR**: backward-compatible functionality.
- **PATCH**: backward-compatible bug fixes.

For complete rules and edge cases, see the official specification: [https://semver.org/spec/v2.0.0.html](https://semver.org/spec/v2.0.0.html)

## SwiftSlash’s SemVer Commitment

- **Strict adherence since v3.0.0**: All releases from v3 onward follow SemVer 2.0.0.
- **Clear communication**:

	- MAJOR bumps (e.g., v3 → v4) may introduce breaking changes.
	- MINOR bumps (e.g., v4.0 → v4.1) add features in a backward-compatible way.
	- PATCH bumps (e.g., v4.0.0 → v4.0.1) fix bugs without API changes.

## Recommended Versions & Branches

| Series | Recommended Version | Branch   | Notes                                                                                            |
| ------ | ------------------- | -------- | ------------------------------------------------------------------------------------------------ |
| **v3** | v3.4.0              | `v3`     | Last stable v3 release. Community-driven maintenance; updates are not officially guaranteed.     |
| **v6** | v6.0.0              | `master` | Current major series. Process-group placement is part of the spawn contract: nested launches cascade, detachment is explicit. |
| **v5** | v5.0.3              | `master` | Read-path termination (a launch settles when its child exits) and non-ASCII argument marshalling fixes. |
| **v4** | v4.0.0              | `master` | Swift 6.x compatibility, enhanced memory control, and ongoing support. |

- Future v3 fixes or minor updates will be merged into the `v3` branch.
- All new v4 development targets the `master` branch.

## Why Choose v4.0.0?

- **Swift 6.x+ Compatibility**: Designed and tested against Swift 6.0 and beyond.
- **Enhanced Memory Control**: Zero-leak guarantees, automated resource scheduling, and stricter safety.
- **Refined API Consistency**: Improvements based on user feedback for clearer naming and defaults.
- **Ongoing Support**: Feature additions and bug fixes will prioritize the v4 series.

**New projects** should start with **v4.0.0**.
Legacy codebases still on v3.x can continue with **v3.4.0** but are encouraged to plan a migration path as the ecosystem continues to evolve into Swift 6.

---

## Migrating to v6.0.0

v6.0.0 makes process-group placement part of the spawn contract. The migration is small, and most callers are unaffected.

| Change | What to do |
| --- | --- |
| `ChildProcess(_:processGroup:)` now resolves its default from the enclosing launch instead of always meaning ``SwiftSlash/ChildProcess/ProcessGroup/own``. | Nothing, unless you depended on "no argument means `.own`" *while running inside a launch*. Pass `processGroup: .own` explicitly to keep that behaviour. |
| ``SwiftSlash/ChildProcess/ProcessGroup`` gained `inherited` and `detached`. | Nothing. `.own` is unchanged. |
| ``SwiftSlash/ChildProcess/signal(_:to:)`` is new, and defaults to `.processGroup`. | Use it instead of signalling a pid by hand. |
| File descriptor 3 is reserved for the launch descriptor. | A program that binds or closes descriptor 3 loses cascading and falls back to its own group. Bind elsewhere. |
| Cancellation signals once and does not escalate. | Pass `SIGKILL` where termination must be guaranteed. This was already the behaviour in v5; v6 documents it as a contract. |

The nested-launch escape is why this is a major bump: a launch's child that itself spawned through SwiftSlash used to form a second process group, so an outer teardown could not reach it and the grandchild survived for minutes after the caller had reported failure. See <doc:Process Groups and Detachment>.

---

*This document was last updated for SwiftSlash v6.0.0*
