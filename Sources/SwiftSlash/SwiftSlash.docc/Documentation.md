#  ``SwiftSlash``

High performance concurrent shell framework built from the ground-up with async/await.

Current Version: `3.2.0`

#### Platform Support
  - Linux
    - Fully supported in all versions

  - MacOS
    - Fully supported with release of tag `3.1.0`

## Getting Started

``Command`` implements a convenience function `runSync()` which serves as a simple way to execute processes with no setup or I/O handling.

```
import SwiftSlash

// EXAMPLE: check the systems ZFS version and print the first line of the output

let commandResult:CommandResult = try await Command(bash:"zfs --version").runSync()

//check the exit code
if commandResult.exitCode == 0 {

    //print the first line of output
    print("Found ZFS version: \( String(data:commandResult.stdout[0], encoding:.utf8) )")
}

```
