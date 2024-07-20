// swift-tools-version:5.9
import PackageDescription

// determine which packages to include as dependencies for the root package based on how the project is configured.
fileprivate var packageDependencies:[Package.Dependency] = []
// #if SWIFTSLASH_SHOULDLOG
// packageDependencies.append(.package(url:"https://github.com/apple/swift-log.git", "1.0.0"..<"2.0.0"))
// #endif

// determine the dependencies for the swiftslash target
fileprivate var targetSwiftSlashDependencies:[Target.Dependency] = [
	"__cswiftslash"
]
// #if SWIFTSLASH_SHOULDLOG
// targetSwiftSlashDependencies.append(.product(name:"Logging", package:"swift-log"))
// #endif

// determine the dependencies for the swiftslash pthread target
fileprivate var targetSwiftSlashPThreadDependencies:[Target.Dependency] = [
	"__cswiftslash",
	"SwiftSlashFuture"
]
// #if SWIFTSLASH_SHOULDLOG
// targetSwiftSlashPThreadDependencies.append(.product(name:"Logging", package:"swift-log"))
// #endif

// determine the dependencies for the swiftslash future target
fileprivate var targetSwiftSlashFutureDependencies:[Target.Dependency] = [
	"__cswiftslash",
	"SwiftSlashContained"
]
// #if SWIFTSLASH_SHOULDLOG
// targetSwiftSlashFutureDependencies.append(.product(name:"Logging", package:"swift-log"))
// #endif

// determine the dependencies for the swiftslash contained target
fileprivate var targetSwiftSlashContainedDependencies:[Target.Dependency] = []
// #if SWIFTSLASH_SHOULDLOG
// targetSwiftSlashContainedDependencies.append(.product(name:"Logging", package:"swift-log"))
// #endif


fileprivate var targetList:[Target] = [
	.target(
		name:"SwiftSlash",
		dependencies:targetSwiftSlashDependencies
	),
	.target(
		name:"SwiftSlashPThread",
		dependencies:targetSwiftSlashPThreadDependencies
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
		name:"__cswiftslash",
		publicHeadersPath:"."),
	
	/// 
	.testTarget(
		name: "InternalPrimitiveTests",
		dependencies:[
			"SwiftSlash",
			"__cswiftslash",
			"SwiftSlashPThread"
		]
	),
]

#if SWIFTSLASH_SHOULDLOG
targetList.append(
	.target(
		name:"SwiftSlashLogging",
		path:"Sources/SwiftSlashLogging",
		dependencies:[
			.product(name:"Logging", package:"swift-log")
		]
	)
)
#endif

let package = Package(
    name:"SwiftSlash",
    platforms:[
        .macOS(.v12)
    ],
    products:[
        .library(
        	name:"SwiftSlash",
            targets:["SwiftSlash"])
    ],
    dependencies:packageDependencies,
    targets:targetList,
	cLanguageStandard:.c11
)
