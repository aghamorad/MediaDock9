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
        )
    ],
    swiftLanguageModes: [.v5]
)
