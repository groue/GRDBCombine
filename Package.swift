// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "GRDBCombine",
    platforms: [
        .macOS("10.15"),
        .iOS("13.0"),
        .watchOS("6.0"),
        .tvOS("13.0"),
    ],
    products: [
        .library(name: "GRDBCombine", targets: ["GRDBCombine"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", .upToNextMajor(from: "4.1.0"))
    ],
    targets: [
        .target(
            name: "GRDBCombine",
            dependencies: ["GRDB"]),
        .testTarget(
            name: "GRDBCombineTests",
            dependencies: ["GRDBCombine", "GRDB"])
    ],
    swiftLanguageVersions: [.v5]
)
