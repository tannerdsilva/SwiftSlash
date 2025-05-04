# ``SwiftSlash/Command``

## Overview

The `Command` structure encapsulates the configuration required to launch an external process from Swift. It defines the executable path, arguments, environment variables, and working directory without performing execution itself.

## Topics

### Core Initializers

- ``SwiftSlash/Command/init(absolutePath:arguments:environment:workingDirectory:)``
- ``SwiftSlash/Command/init(_:arguments:environment:workingDirectory:)``

### Shell-Wrapped Initializers

- ``SwiftSlash/Command/init(sh:environment:workingDirectory:)``

### Instance Variables

- ``SwiftSlash/Command/executable``
- ``SwiftSlash/Command/arguments``
- ``SwiftSlash/Command/environment``
- ``SwiftSlash/Command/workingDirectory``

### Transferring Environment Variables

- ``SwiftSlash/Command/inheritCurrentEnvironment()``
