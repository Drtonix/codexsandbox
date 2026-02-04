// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WaveKeyboardApp",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "WaveKeyboardApp"
        ),
    ]
)
