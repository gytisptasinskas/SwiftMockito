// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PluginFixture",
    platforms: [.macOS(.v26), .iOS(.v26)],   // match the root package (D1)
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
