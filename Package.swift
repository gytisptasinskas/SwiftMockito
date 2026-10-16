// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftMockito",
    platforms: [.macOS(.v26), .iOS(.v26)],   // Task.immediate (resolved D1)
    products: [
        .library(name: "SwiftMockito", targets: ["SwiftMockito"]),
    ],
    targets: [
        .target(name: "SwiftMockito"),
        .testTarget(name: "SwiftMockitoTests", dependencies: ["SwiftMockito"]),
    ],
    swiftLanguageModes: [.v6]
)
