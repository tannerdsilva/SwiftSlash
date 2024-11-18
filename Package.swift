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
		dependencies:["__cswiftslash_types"],
		publicHeadersPath:"."
	),
	// future
	.target(
		name:"__cswiftslash_future",
		dependencies:[
			"__cswiftslash_identified_list",
			"__cswiftslash_types"
		],
		publicHeadersPath:"."
	),
	// threading
	.target(
		name:"__cswiftslash_threads",
		dependencies:["__cswiftslash_types"],
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
		dependencies:["__cswiftslash_types"],
		publicHeadersPath:"."
	),
	// unit tests for all c targets
	// .testTarget(
	// 	name:"__cswiftslash_tests",
	// 	dependencies:[
	// 		"__cswiftslash_auint8",
	// 		"__cswiftslash_fifo",
	// 		"__cswiftslash_future",
	// 		"__cswiftslash_types",
	// 		"__cswiftslash_threads",
	// 		"__cswiftslash_eventtrigger",
	// 		"__cswiftslash_identified_list"
	// 	],
	// 	path: "Tests/__cswiftslash"
	// )
]

fileprivate let swiftTargets:[Target] = [
	.target(
		name:"SwiftSlashContained"
	),
	.target(
		name:"SwiftSlashFuture",
		dependencies:[
			"__cswiftslash_future",
			"SwiftSlashContained"
		]
	),
	// .testTarget(
	// 	name:"SwiftSlashFutureTests",
	// 	dependencies:[
	// 		"SwiftSlashFuture",
	// 		"__cswiftslash_auint8",
	// 	],
	// 	path:"Tests/SwiftSlashFutureTests"
	// ),
	/*.testTarget(
		name:"SwiftSlashPThreadTests",
		dependencies:[
			"SwiftSlashFuture",
			"SwiftSlashContained",
			"__cswiftslash_threads",
			"SwiftSlashPThread"
		],
		path:"Tests/SwiftSlashPThreadTests"
	),*/
	.target(
		name:"SwiftSlashPThread",
		dependencies:[
			"__cswiftslash_threads",
			"SwiftSlashContained",
			"SwiftSlashFuture"
		]
	)
]

fileprivate let testTarget:Target = .testTarget(
	name:"SwiftSlashInternalTests",
	dependencies:[
		// "__cswiftslash_auint8",
		"__cswiftslash_fifo",
		"__cswiftslash_future",
		"__cswiftslash_types",
		"__cswiftslash_threads",
		"__cswiftslash_eventtrigger",
		"__cswiftslash_identified_list",
		"SwiftSlashFuture",
		"SwiftSlashContained",
		"SwiftSlashPThread"
	],
	path:"Tests/SwiftSlashInternalTests"
)

fileprivate var ssInternalTargets:[Target] = cswiftslashTargets + swiftTargets + [testTarget] /* + [
	.target(
		name:"SwiftSlash",
		dependencies:[
			"SwiftSlashPThread",
			"SwiftSlashFuture",
			"SwiftSlashFIFO",
			"SwiftSlashIdentifiedList",
			"SwiftSlashNAsyncStream",
			"SwiftSlashFHHelpers",
			"SwiftSlashLineParser",
		]
	),
	.target(
		name:"SwiftSlashLineParser",
		dependencies:[
			// "__cswiftslash",
			"SwiftSlashNAsyncStream"	
		]
	),
	.target(
		name:"SwiftSlashNAsyncStream",
		dependencies:[
			"SwiftSlashFIFO",
			"SwiftSlashIdentifiedList"
		]
	),
	.target(
		name:"SwiftSlashFHHelpers",
		dependencies:["__cswiftslash_posix_helpers"]
	),
	.target(
		name:"SwiftSlashPThread",
		dependencies:[
			"__cswiftslash_threads",
			"SwiftSlashFuture"
		]
	),
	.target(
		name:"SwiftSlashFuture",
		dependencies:[
			"__cswiftslash_future",
			"SwiftSlashContained"
		]
	),
	.target(
		name:"SwiftSlashContained"
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
		name:"SwiftSlashEventTrigger",
		dependencies:[
			"__cswiftslash_eventtrigger",
			"SwiftSlashPThread",
			"SwiftSlashFIFO"
		]
	),
	.target(
		name:"__cswiftslash_future",
		dependencies:[
			"__cswiftslash_types",
			"__cswiftslash_fifo"
		],
		publicHeadersPath:"."),
	.target(
		name:"__cswiftslash_threads",
		dependencies:["__cswiftslash_types"],
		publicHeadersPath:"."
	),
	.target(
		name:"__cswiftslash_identified_list",
		dependencies:["__cswiftslash_types"],
		publicHeadersPath:"."
	),
	.target(
		name:"__cswiftslash_posix_helpers",
		dependencies:[],
		publicHeadersPath:"."
	),
	// test target
	/*.testTarget(
		name: "InternalPrimitiveTests",
		dependencies:[
			"SwiftSlash",
			"__cswiftslash",
			"SwiftSlashPThread",
			"SwiftSlashFuture",
			"SwiftSlashContained",
			"SwiftSlashIdentifiedList",
			"SwiftSlashFIFO",
			"SwiftSlashNAsyncStream",
			"SwiftSlashFHHelpers",
			"SwiftSlashLineParser",
			"SwiftSlashEventTrigger"
		]
	)*/
]*/


let package = Package(
	name:"SwiftSlash",
	platforms:[
		.macOS(.v15) // NO SANDBOXING
	],
	products:[
		.library(
			name:"SwiftSlash",
			targets:["SwiftSlashContained"])
	],
	targets:ssInternalTargets,
	cLanguageStandard:.c11
)
