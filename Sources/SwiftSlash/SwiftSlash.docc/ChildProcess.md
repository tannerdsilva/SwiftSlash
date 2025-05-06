# ``SwiftSlash/ChildProcess``

## Topics

### Initialize a New Instance

- ``SwiftSlash/ChildProcess/init(_:dataChannels:)``

### Run the Process

- ``SwiftSlash/ChildProcess/run()``
- ``SwiftSlash/ChildProcess/Exit``

### Signaling a Running Process

- ``SwiftSlash/ChildProcess/signal(_:)``
- ``SwiftSlash/ChildProcess/SignalError``

### Process Lifecycle State

- ``SwiftSlash/ChildProcess/State``
- ``SwiftSlash/ChildProcess/state``
- ``SwiftSlash/ChildProcess/InvalidProcessStateError``

### Accessing Default Data Channels (Convenient)

- ``SwiftSlash/ChildProcess/stdin``
- ``SwiftSlash/ChildProcess/stdout``
- ``SwiftSlash/ChildProcess/stderr``

### Accessing Any Data Channel (Explicit)

- ``SwiftSlash/ChildProcess/subscript(channel:)``
- ``SwiftSlash/ChildProcess/subscript(writer:)``
- ``SwiftSlash/ChildProcess/subscript(reader:)``

### Runtime Errors

- ``SwiftSlash/ChildProcess/ReapError``
- ``SwiftSlash/ChildProcess/SpawnError``

### Other Instance Properties

- ``SwiftSlash/ChildProcess/command``
