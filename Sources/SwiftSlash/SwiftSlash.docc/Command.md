# ``SwiftSlash/Command``
The `Command` structure is used to define a command, or process, that can be executed from within a Swift program.

## Instance Variables
``SwiftSlash/Command`` is a basic structure that is comprised of four instance variables. Each of these inatance variables are discussed below...

### Executable Path
The ``SwiftSlash/Command/executable`` variable is a string that specifies the absolute path to the executable that will be run. This path must point to a valid executable on the system in order for the command to be executed successfully. There are several convenience functions that can resolve an explicit path from an implied program name. In many cases, this is the most intuitive way to initialize a ``SwiftSlash/Command`` structure.

### Arguments
The ``SwiftSlash/Command/arguments`` variable is an array of strings that contains the arguments to be passed into the executable when it is launched. These arguments are provided as separate strings and should be ordered in the same way they would be if you were running the command from the command line.

### Environment Variables
The ``SwiftSlash/Command/environment`` variable is a dictionary of key-value string pairs that represents the environment variables that will be assigned to the process at launch time. These variables are typically used to provide additional configuration or context to the executable as it runs.

### Working Directory
The ``SwiftSlash/Command/workingDirectory`` variable is a string that specifies the working directory assigned to the process when it launches. This is the directory where the executable will start running, and it may be different from, and will not interfere with or override, the directory where the Swift program itself is located.

## Discussion
The ``SwiftSlash/Command`` structure is a simple way to define a command to be executed from within a Swift program. It's important to note that the `Command` structure does not actually launch the command itself. Rather, it simply defines the launch plan (or template) for the command. In SwiftSlash, launches happen by initializing a ``SwiftSlash/ProcessInterface`` with a ``SwiftSlash/Command``. However, `Command` implements a convenience function ``SwiftSlash/Command/runSync()`` that allows a command to be launched without interacting with a ``SwiftSlash/ProcessInterface`` instance.

## Topics

### Direct Initializers

- ``SwiftSlash/Command/init(absolutePath:arguments:environment:workingDirectory:)``

- ``SwiftSlash/Command/init(_:arguments:environment:workingDirectory:)``

### Shell-Wrapped Initializers

- ``SwiftSlash/Command/init(zsh:environment:workingDirectory:)``

- ``SwiftSlash/Command/init(bash:environment:workingDirectory:)``

### Instance Variables

- ``SwiftSlash/Command/executable``

- ``SwiftSlash/Command/arguments``

- ``SwiftSlash/Command/environment``

- ``SwiftSlash/Command/workingDirectory``

### Run a Command

- ``SwiftSlash/Command/runSync()``
