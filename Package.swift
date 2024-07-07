// swift-tools-version:5.9
import PackageDescription
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
    dependencies:[
		.package(url:"https://github.com/apple/swift-log.git", "1.0.0"..<"2.0.0") // supports all known major releases of swift-log
	],
    targets: [
        .target(
            name: "SwiftSlash",
            dependencies:[
				.product(name:"Logging", package:"swift-log"),
				"__cswiftslash"
			]),
        .target(
        	name:"__cswiftslash",
			publicHeadersPath:".",
			cSettings: []),
        .testTarget(
            name: "SwiftSlashTests",
            dependencies: ["SwiftSlash", "__cswiftslash"]),
    ],
	cLanguageStandard:.c11
)
