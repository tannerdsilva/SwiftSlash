# ``SwiftSlash/ChildProcess``

## Topics

### Initialize a New Instance

- ``SwiftSlash/ChildProcess/init(_:dataChannels:)``

### Run the Process

- ``SwiftSlash/ChildProcess/run()``
- ``SwiftSlash/ChildProcess/Exit``

### Process Lifecycle State

- ``SwiftSlash/ChildProcess/State``
- ``SwiftSlash/ChildProcess/state``

### Other Instance Properties

- ``SwiftSlash/ChildProcess/command``

### Accessing Data Channels (Convenient)

- ``SwiftSlash/ChildProcess/stdin``
- ``SwiftSlash/ChildProcess/stdout``
- ``SwiftSlash/ChildProcess/stderr``

### Accessing Data Channels (Explicit)

- ``SwiftSlash/ChildProcess/subscript(channel:)``
- ``SwiftSlash/ChildProcess/subscript(writer:)``
- ``SwiftSlash/ChildProcess/subscript(reader:)``

### Errors Regarding Child Processes

- ``SwiftSlash/ChildProcess/InvalidProcessStateError``
- ``SwiftSlash/ChildProcess/ReapError``
- ``SwiftSlash/ChildProcess/SpawnError``
