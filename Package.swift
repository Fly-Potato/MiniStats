// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniStats",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MiniStats", targets: ["MiniStats"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .executableTarget(name: "MiniStats", dependencies: [.product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "MiniStatsTests", dependencies: ["MiniStats"])
    ]
)
