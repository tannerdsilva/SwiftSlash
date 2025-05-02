# ``SwiftSlash/Path``

Represents and manipulates filesystem paths on the host system in a platform-agnostic way.

## Overview

A **system path** is a sequence of directory or file names separated by a platform-specific delimiter (typically `/` on Unix-like systems). Internally, `Path` stores each segment as a separate string in its `components` array. When converted back to a full path string, segments are joined with `/` and prefixed with a leading slash to denote an absolute path.

This structure handles:

* **Absolute vs. relative paths**: You can initialize from either form; an absolute path begins with `/`, while relative paths lack the leading slash and can be resolved against a working directory if needed.
* **Normalization**: Empty segments are omitted when parsing, and `..` or `.` resolution can be layered on top by client code if necessary.
* **Platform differences**: While this implementation assumes `/` separators, it can be extended to support other separators (e.g., `\` on Windows) by normalizing input/output.

## Declaration

```swift
public struct Path: Sendable {
    private var components: [String]
}
```

Stores each path segment in the `components` array.

## Properties

### `components: [String]`

Private array of path segments. Each element represents a directory or filename.

## Initializers

### `init<S>(_ pathString: S) where S: StringProtocol, S.SubSequence == Substring`

Parses a string into path components by splitting on `/`.

* **Parameter** `pathString`: A valid filesystem path string (absolute or relative).

### `init(pathComponents: [String])`

Constructs a `Path` directly from an array of segments.

* **Parameter** `pathComponents`: Ordered segments without separators.

## Instance Methods

### `mutating func appendPathComponent(_ component: String)`

Adds a new segment to the end of `components`.

* **Parameter** `component`: Directory or filename to append.

### `func appendingPathComponent(_ component: String) -> Path`

Returns a new `Path` with an appended segment, leaving the original unchanged.

* **Parameter** `component`: Segment to add.
* **Returns**: A new `Path` including the appended component.

### `mutating func removeLastComponent()`

Removes the final segment from `components`.

### `func removingLastComponent() -> Path`

Returns a new `Path` without its last segment.

### `func path() -> String`

Reassembles `components` into a full path string.

* Joins segments with `/`.
* Prepends `/` to indicate an absolute path.
* **Returns**: A `String` representation of the path.

## Protocol Conformances

### `CustomStringConvertible`

* **`var description: String`** — Returns the result of `path()`.

### `CustomDebugStringConvertible`

* **`var debugDescription: String`** — Returns `"Path(\"\(path())\")"`.

### `ExpressibleByStringLiteral`

* **`init(stringLiteral value: String)`** — Allows creation via string literals (e.g., `let p: Path = "/usr/bin"`).

### `Hashable` & `Equatable`

* **`func hash(into:)`** — Combines `components` for hashing.
* **`static func ==`** — Returns true when `components` arrays are equal.

## Mechanical Details

* **Parsing**: Splitting uses `String.split(separator: "/")` which omits empty components to avoid `//` artifacts.
* **Storage**: Keeping `components` separate allows O(1) additions/removals at the end and easy relative path manipulations.
* **String Conversion**: On `path()`, segments are joined and prefixed. Clients requiring relative paths can drop the leading slash.

By modeling paths as arrays of segments rather than flat strings, `Path` ensures reliable, predictable operations on filesystem paths with zero ambiguity around separators or trailing slashes.
