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
	// fifo
	.target(
		name:"__cswiftslash_fifo",
		dependencies: [
			"__cswiftslash_types"
		],
		publicHeadersPath:"."
	),
	// future
	.target(
		name:"__cswiftslash_future",
		dependencies: [
			"__cswiftslash_identified_list",
			"__cswiftslash_types"
		],
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
	// identified list
	.target(
		name:"__cswiftslash_identified_list",
		dependencies: [
			"__cswiftslash_types"
		],
		publicHeadersPath:"."
	),
]

fileprivate let swiftTargets:[Target] = [
	.target(
		name:"SwiftSlashContained"
	),
	.target(
		name:"SwiftSlashGlobalSerialization"
	),
	.target(
		name:"SwiftSlashFuture",
		dependencies:[
			"__cswiftslash_future",
			"SwiftSlashContained"
		]
	),
	.target(
		name:"SwiftSlashPThread",
		dependencies:[
			"__cswiftslash_threads",
			"SwiftSlashContained",
			"SwiftSlashFuture"
		]
	),
	.target(
		name:"SwiftSlashIdentifiedList",
		dependencies:[
			"__cswiftslash_identified_list",
			"SwiftSlashContained"
		]
	),
	.target(
		name:"SwiftSlashFIFO",
		dependencies:[
			"__cswiftslash_fifo",
			"SwiftSlashContained"
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
			"SwiftSlashFHHelpers"
		]
	),
	.target(
		name:"SwiftSlash",
		dependencies:[
			"SwiftSlashPThread",
			"SwiftSlashFuture",
			"SwiftSlashFIFO",
			"SwiftSlashIdentifiedList",
			"SwiftSlashFHHelpers",
			"SwiftSlashEventTrigger",
			"SwiftSlashGlobalSerialization"
		]
	),
]

fileprivate let testTarget:Target = .testTarget(
	name:"SwiftSlashInternalTests",
	dependencies:[
		"__cswiftslash_fifo",
		"__cswiftslash_future",
		"__cswiftslash_types",
		"__cswiftslash_threads",
		"__cswiftslash_eventtrigger",
		"__cswiftslash_identified_list",
		"SwiftSlashFuture",
		"SwiftSlashContained",
		"SwiftSlashPThread",
		"SwiftSlashIdentifiedList",
		"SwiftSlashFIFO",
		"SwiftSlashEventTrigger",
		"SwiftSlash",
	],
	path:"Tests/SwiftSlashInternalTests"
)

fileprivate var ssInternalTargets:[Target] = cswiftslashTargets + swiftTargets + [testTarget]

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
