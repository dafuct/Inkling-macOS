// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Inkling",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMajor(from: "1.3.0")),
    ],
    targets: [
        .target(name: "InklingCore"),
        .target(
            name: "InklingMLX",
            dependencies: [
                "InklingCore",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Inkling",
            dependencies: [
                "InklingCore",
                "InklingMLX",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "Hub", package: "swift-transformers"),
            ],
            swiftSettings: [
                // macOS C frameworks (ApplicationServices) + AppKit aren't annotated
                // for Swift 6 strict concurrency; this target builds in language mode 5.
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "InklingBench",
            dependencies: [
                "InklingCore",
                "InklingMLX",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "InklingCoreTests",
            dependencies: ["InklingCore"]
        ),
    ]
)
