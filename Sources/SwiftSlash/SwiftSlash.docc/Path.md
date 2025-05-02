# ``SwiftSlash/Path``

Represents and manipulates filesystem paths on the host system in a platform-agnostic way.

## Overview

A **system path** is a sequence of directory or file names separated by a platform-specific delimiter (typically `/` on Unix-like systems). Internally, `Path` stores each segment as a separate string in its `components` array. When converted back to a full path string, segments are joined with `/` and prefixed with a leading slash to denote an absolute path.

## Declaration

```swift
public struct Path: Sendable {
    private var components: [String]
}
```

## Topics

### Instance Initializers

- ``SwiftSlash/Path/init(_:)``
- ``SwiftSlash/Path/init(pathComponents:)``

### Mutating Existing Memory

- ``SwiftSlash/Path/appendPathComponent(_:)``
- ``SwiftSlash/Path/removeLastComponent()``

### Modify by Copy

- ``SwiftSlash/Path/appendingPathComponent(_:)``
- ``SwiftSlash/Path/removingLastComponent()``

### Path String Value

- ``SwiftSlash/Path/path()``
