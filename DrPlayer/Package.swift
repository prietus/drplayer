// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DrPlayer",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DrPlayer",
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
