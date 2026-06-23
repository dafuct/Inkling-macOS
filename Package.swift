// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Inkling",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "InklingCore"),
        .executableTarget(
            name: "Inkling",
            dependencies: ["InklingCore"],
            swiftSettings: [
                // The macOS C frameworks (ApplicationServices) and AppKit are not
                // annotated for Swift 6 strict concurrency. This spike does all its
                // work on the main run loop, so build this target in language mode 5
                // rather than scatter @preconcurrency/@MainActor through the OS glue.
                // Revisit when hardening after Phase 0.
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "InklingCoreTests",
            dependencies: ["InklingCore"]
        ),
    ]
)
