# Versioning

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
| **v4** | v4.0.0              | `master` | Current major series with Swift 6.x compatibility, enhanced memory control, and ongoing support. |

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

*This document was last updated for SwiftSlash v4.0.0*
