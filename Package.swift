// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniStats",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MiniStats", targets: ["MiniStats"])],
    targets: [
        .executableTarget(name: "MiniStats"),
        .testTarget(name: "MiniStatsTests", dependencies: ["MiniStats"])
    ]
)
