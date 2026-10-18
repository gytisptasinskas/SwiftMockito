// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PluginFixture",
    platforms: [.macOS(.v14), .iOS(.v17)],   // match the root package
    dependencies: [.package(name: "SwiftMockito", path: "../..")],
    targets: [
        .target(name: "App"),
        .testTarget(
            name: "AppTests",
            dependencies: ["App", .product(name: "SwiftMockito", package: "SwiftMockito")],
            plugins: [.plugin(name: "SwiftMockitoPlugin", package: "SwiftMockito")]
        ),
    ]
)
