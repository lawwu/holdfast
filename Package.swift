// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "holdfast",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "holdfast", targets: ["holdfast"])],
    dependencies: [
        .package(path: "Packages/pi-swift-mlx/swift"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "3.32.3"),  // pinned to releases, not main
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "holdfast",
            dependencies: [
                .product(name: "LocalMLX", package: "swift"),
                .product(name: "ModelProviders", package: "swift"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXRerankers", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "Hub", package: "swift-transformers"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
    ]
)
