// swift-tools-version: 6.2

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "SwiftMockito",
    platforms: [.macOS(.v26), .iOS(.v26)],   // Task.immediate (resolved D1)
    products: [
        .library(name: "SwiftMockito", targets: ["SwiftMockito"]),
        .executable(name: "SwiftMockitoGenerator", targets: ["SwiftMockitoGenerator"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"700.0.0"),
    ],
    targets: [
        .macro(
            name: "SwiftMockitoMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
        ),
        .target(name: "SwiftMockito", dependencies: ["SwiftMockitoMacros"]),
        .testTarget(name: "SwiftMockitoTests", dependencies: ["SwiftMockito"]),
        .target(
            name: "SwiftMockitoGeneratorCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .executableTarget(name: "SwiftMockitoGenerator", dependencies: ["SwiftMockitoGeneratorCore"]),
        .testTarget(
            name: "GeneratorTests",
            dependencies: [
                "SwiftMockitoGeneratorCore",
                "SwiftMockitoMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
