// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

// release build does not have any dependencies. debug build has swift-log
// #if DEBUG
let packDeps:[PackageDescription.Package.Dependency] = [
//    .package(url:"https://github.com/apple/swift-log.git", from:"1.4.2")
]
let targetDeps:[PackageDescription.Target.Dependency] = [
//    .product(name:"Logging", package:"swift-log"),
    "ClibSwiftSlash"
]
// #else
// let packDeps:[PackageDescription.Package.Dependency] = []
// let targetDeps:[PackageDescription.Target.Dependency] = [
//     "ClibSwiftSlash"
// ]
// #endif

import PackageDescription
let package = Package(
    name: "SwiftSlash",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "SwiftSlash",
            targets: ["SwiftSlash"])
    ],
    dependencies: packDeps,
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "SwiftSlash",
            dependencies: targetDeps),
        .target(
        	name: "ClibSwiftSlash",
        	dependencies: []),
        .testTarget(
            name: "SwiftSlashTests",
            dependencies: ["SwiftSlash"]),
    ]
)
