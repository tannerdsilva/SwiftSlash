// swift-tools-version:5.9
import PackageDescription

fileprivate var ssInternalTargets:[Target] = [
	.target(
		name:"SwiftSlash",
		dependencies:[
			"__cswiftslash",
			"SwiftSlashPThread",
			"SwiftSlashFuture",
			"SwiftSlashFIFO",
			"SwiftSlashIdentifiedList",
			"SwiftSlashNAsyncStream",
			"SwiftSlashFHHelpers",
		]
	),
	.target(
		name:"SwiftSlashLineParser",
		dependencies:[
			"__cswiftslash",
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
		dependencies:["__cswiftslash"]
	),
	.target(
		name:"SwiftSlashPThread",
		dependencies:[
			"__cswiftslash",
			"SwiftSlashFuture"
		]
	),
	.target(
		name:"SwiftSlashFuture",
		dependencies:[
			"__cswiftslash",
			"SwiftSlashContained"
		]
	),
	.target(
		name:"SwiftSlashContained"
	),
	.target(
		name:"SwiftSlashIdentifiedList",
		dependencies:[
			"__cswiftslash",
			"SwiftSlashContained"
		]
	),
	.target(
		name:"SwiftSlashFIFO",
		dependencies:[
			"__cswiftslash",
			"SwiftSlashContained"
		]
	),
	.target(
		name:"SwiftSlashEventTrigger",
		dependencies:[
			"__cswiftslash",
			"SwiftSlashPThread",
			"SwiftSlashFIFO"
		]
	),
	.target(
		name:"__cswiftslash",
		publicHeadersPath:"."),
	
	// test target
	.testTarget(
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
	),
]


let package = Package(
	name:"SwiftSlash",
	platforms:[
		.macOS(.v12) // NO SANDBOXING
	],
	products:[
		.library(
			name:"SwiftSlash",
			targets:["SwiftSlash"])
	],
	targets:ssInternalTargets,
	cLanguageStandard:.c11
)
