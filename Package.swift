// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SlopSandbox",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .target(
            name: "CBox2D",
            path: "Vendor/box2d",
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("src")
            ]
        ),
        .executableTarget(
            name: "SlopSandbox",
            dependencies: ["CBox2D"]
        ),
    ]
)
