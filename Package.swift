// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VinylPod",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VinylPod",
            path: "Sources/VinylPod",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
