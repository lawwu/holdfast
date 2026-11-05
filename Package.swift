// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "mac-kb",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "mackb", targets: ["mackb"])],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "mackb",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
    ]
)
