// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LyricServices",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "LyricServices",
            targets: ["LyricServices"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "LyricServices",
            dependencies: []),
        .testTarget(
            name: "LyricServicesTests",
            dependencies: ["LyricServices"]),
    ]
)
