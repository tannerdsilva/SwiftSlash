// swift-tools-version:5.9
import PackageDescription

// determine the dependencies for the swiftslash pthread target
fileprivate var targetSwiftSlashPThreadDependencies:[Target.Dependency] = [
	"__cswiftslash",
	"SwiftSlashFuture"
]

// determine the dependencies for the swiftslash future target
fileprivate var targetSwiftSlashFutureDependencies:[Target.Dependency] = [
	"__cswiftslash",
	"SwiftSlashContained"
]

// determine the dependencies for the swiftslash contained target
fileprivate var targetSwiftSlashContainedDependencies:[Target.Dependency] = []

fileprivate var ssInternalTargets:[Target] = [
	.target(
		name:"SwiftSlash",
		dependencies:[
			"__cswiftslash",
			"SwiftSlashPThread",
			"SwiftSlashFuture",
			"SwiftSlashFIFO",
			"SwiftSlashIdentifiedList"
		]
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
		dependencies:targetSwiftSlashFutureDependencies
	),
	.target(
		name:"SwiftSlashContained",
		dependencies:targetSwiftSlashContainedDependencies
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
	
	/// 
	.testTarget(
		name: "InternalPrimitiveTests",
		dependencies:[
			"SwiftSlash",
			"__cswiftslash",
			"SwiftSlashPThread",
			"SwiftSlashFuture",
			"SwiftSlashContained",
			"SwiftSlashIdentifiedList",
			"SwiftSlashFIFO"
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
