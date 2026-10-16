// swift-tools-version:6.0
import PackageDescription

fileprivate let cswiftslashTargets:[Target] = [
	// event trigger
	.target(
		name:"__cswiftslash_eventtrigger",
		publicHeadersPath:"."
	),
	// basic c types
	.target(
		name:"__cswiftslash_types",
		publicHeadersPath:"."
	),
	// threading
	.target(
		name:"__cswiftslash_threads",
		dependencies: [
			"__cswiftslash_types"
		],
		publicHeadersPath:"."
	),
	// posix helpers
	.target(
		name:"__cswiftslash_posix_helpers",
		publicHeadersPath:"."
	),
]

fileprivate let swiftTargets:[Target] = [
	.target(
		name:"SwiftSlashPThreadSerialExecutor",
		dependencies:[
			"SwiftSlashPThread",
			"SwiftSlashFIFO",
			"__cswiftslash_threads"
		]
	),
	.target(
		name:"SwiftSlashGlobalSerialization",
		dependencies:[
			"SwiftSlashPThreadSerialExecutor",
			"SwiftSlashFIFO",
			"SwiftSlashPThread",
		]
	),
	.target(
		name:"SwiftSlashFuture",
		dependencies:[
			"SwiftSlashOneShotLatch",
		],
	),
	.target(
		name:"SwiftSlashOneShotLatch"
	),
	.target(
		name:"SwiftSlashPThread",
		dependencies:[
			"__cswiftslash_threads",
			"SwiftSlashFuture"
		]
	),
	.target(
		name:"SwiftSlashFIFO",
		dependencies:[
			"SwiftSlashOneShotLatch"
		]
	),
	.target(
		name:"SwiftSlashFHHelpers",
		dependencies:[
			"__cswiftslash_posix_helpers"
		]
	),
	.target(
		name:"SwiftSlashEventTrigger",
		dependencies:[
			"__cswiftslash_eventtrigger",
			"SwiftSlashPThread",
			"SwiftSlashFIFO",
			"SwiftSlashFHHelpers",
			"SwiftSlashGlobalSerialization"
		]
	),
	.target(
		name:"SwiftSlash",
		dependencies:[
			"SwiftSlashPThread",
			"SwiftSlashFuture",
			"SwiftSlashFIFO",
			"SwiftSlashFHHelpers",
			"SwiftSlashEventTrigger",
			"SwiftSlashGlobalSerialization"
		]
	),
]

// test fixtures. an executable target with NO product: it exists so the
// process-group suite can drive a real second process that itself spawns
// through swiftslash, and it is deliberately absent from the package's
// published surface. the test target depends on it so that it is always built;
// no test imports it.
fileprivate let fixtureTargets:[Target] = [
	.executableTarget(
		name:"SwiftSlashTestSpawner",
		dependencies:[
			"SwiftSlash",
			"__cswiftslash_posix_helpers"
		],
		path:"Tests/SwiftSlashTestSpawner"
	),
]

fileprivate let testTarget:Target = .testTarget(
	name:"SwiftSlashInternalTests",
	dependencies:[
		"__cswiftslash_types",
		"__cswiftslash_threads",
		"__cswiftslash_eventtrigger",
		"SwiftSlashFuture",
		"SwiftSlashPThread",
		"SwiftSlashFIFO",
		"SwiftSlashEventTrigger",
		"SwiftSlash",
		"SwiftSlashGlobalSerialization",
		"SwiftSlashOneShotLatch",
		"SwiftSlashTestSpawner",
	],
	path:"Tests/SwiftSlashInternalTests"
)

fileprivate var ssInternalTargets:[Target] = cswiftslashTargets + swiftTargets + fixtureTargets + [testTarget]

let package = Package(
	name:"SwiftSlash",
	platforms:[
		.macOS(.v15) // NO SANDBOXING
	],
	products:[
		.library(
			name:"SwiftSlash",
			targets:["SwiftSlash"])
	],
	targets:ssInternalTargets,
	cLanguageStandard:.c11
)
