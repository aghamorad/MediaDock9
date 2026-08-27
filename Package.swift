// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MediaDock9",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MediaDock9", targets: ["MediaDock9"])
    ],
    targets: [
        .executableTarget(
            name: "MediaDock9",
            path: "Sources/MediaDock9"
        ),
        .testTarget(
            name: "MediaDock9Tests",
            dependencies: ["MediaDock9"],
            path: "Tests/MediaDock9Tests"
        )
    ],
    swiftLanguageModes: [.v5]
)
