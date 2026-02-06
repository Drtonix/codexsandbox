// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SlopSandbox",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "SlopSandbox"
        ),
    ]
)
