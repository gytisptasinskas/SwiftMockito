// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftMockito",
    products: [
        .library(
            name: "SwiftMockito",
            targets: ["SwiftMockito"]
        )
    ],
    targets: [
        .target(
            name: "SwiftMockito"
        ),
        .testTarget(
            name: "SwiftMockitoTests",
            dependencies: ["SwiftMockito"]
        )
    ]
)
