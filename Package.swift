// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ClaudeCodeSDK",
    platforms: [
         .iOS(.v15),
         .macOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ClaudeCodeSDK",
            targets: ["ClaudeCodeSDK"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        .package(url: "https://github.com/superwall/SwiftAnthropic", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ClaudeCodeSDK",
            dependencies: [
               .product(name: "SwiftAnthropic", package: "SwiftAnthropic"),
            ]),
        .testTarget(
            name: "ClaudeCodeSDKTests",
            dependencies: ["ClaudeCodeSDK"]
        ),
    ]
)
