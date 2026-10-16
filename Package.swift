// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MockitoSwift",
    products: [
        .library(
            name: "MockitoSwift",
            targets: ["MockitoSwift"]
        )
    ],
    targets: [
        .target(
            name: "MockitoSwift"
        ),
        .testTarget(
            name: "MockitoSwiftTests",
            dependencies: ["MockitoSwift"]
        )
    ]
)
