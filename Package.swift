// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cotypist",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CotypistCore"),
        .executableTarget(
            name: "Cotypist",
            dependencies: ["CotypistCore"]
        ),
        .testTarget(
            name: "CotypistCoreTests",
            dependencies: ["CotypistCore"]
        ),
    ]
)
