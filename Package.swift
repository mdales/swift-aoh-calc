// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "persistence-calculator",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(path: "../swift-yirgacheffe"),
        .package(path: "../swift-graphics"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.2"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.1"),
        .package(url: "https://github.com/fwcd/swift-cairo.git", from: "1.3.3")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .executableTarget(
            name: "persistence-calculator",
            dependencies: [
                .product(name: "Yirgacheffe", package: "swift-yirgacheffe"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "Cairo", package: "swift-cairo"),
                .product(name: "CairoGraphics", package: "swift-graphics")
            ]),
        .testTarget(
            name: "persistence-calculatorTests",
            dependencies: ["persistence-calculator"]),
    ]
)
