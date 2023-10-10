// swift-tools-version:5.5
import PackageDescription

#if SWIFTSLASH_LOG_ENABLE

// this lists the dependencies that are needed to build this package.
// - note: this is the value for this variable when logging is ENABLED.
let packageDependencies:[Package.Dependency] = [
	.package(
		url:"https://github.com/apple/swift-log.git",
		from:"1.0.0"
	)
]

// this is the main library that is exposed to the user.
// - note: this is the value for this variable when logging is ENABLED.
let publicSwiftSlashTarget:Target = .target(
	name:"SwiftSlash",
	dependencies:[
		.product(name:"Logging", package:"swift-log"),
		"CSwiftSlash"
	]
)

#else

// this lists the depencies that are needed to build this package.
// - note: this is the value for this variable when logging is DISABLED.
let packageDependencies:[Package.Dependency] = []

let publicSwiftSlashTarget:Target = .target(
	name:"SwiftSlash",
	dependencies:[
		"CSwiftSlash"
	]
)

#endif

// this is the c library that facilitates the system calls that are needed to make SwiftSlash operable.
let internalClibTarget:Target = .target(
	name:"CSwiftSlash",
	cSettings: [
		.define("_GNU_SOURCE", to:"1", .when(platforms:[.linux])),
	]
)

// this is the target that is used to test the SwiftSlash library.
let internalTestTarget:Target = .testTarget(
	name:"SwiftSlashTests",
	dependencies:[
		"SwiftSlash"
	]
)

// this is the list of targets that are used to build this package.
let packageTargets = [
	publicSwiftSlashTarget,
	internalClibTarget,
	internalTestTarget
]

// this is the main package definition.
let package = Package(
    name:"SwiftSlash",
    platforms:[
        .macOS(.v12)
    ],
    products:[
        .library(
        	name:"SwiftSlash",
            targets:[
				"SwiftSlash"
			]
		)
    ],
    dependencies:packageDependencies,
    targets:packageTargets
)
