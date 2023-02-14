// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

fileprivate let cpuCount = ProcessInfo.processInfo.processorCount

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
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
		.package(url:"https://github.com/tannerdsilva/SwiftBCrypt.git", .upToNextMinor(from:"0.2.0"))
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "SwiftSlash",
            dependencies: ["ClibSwiftSlash"]),
        .target(
        	name: "ClibSwiftSlash",
			dependencies: [],
			cSettings:[.define("SS_CPUNUM", to:"\(cpuCount)")]),
        .testTarget(
            name: "SwiftSlashTests",
            dependencies: ["SwiftSlash"]),
    ]
)
