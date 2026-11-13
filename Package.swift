// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "holdfast",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "holdfast", targets: ["holdfast"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.1"),
        .package(path: "Packages/LocalMLX"),
        .package(path: "Packages/ModelProviders"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.18.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "3.32.3"),  // pinned to releases, not main
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.0.0"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "holdfast",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "LocalMLX", package: "localmlx"),
                .product(name: "ModelProviders", package: "modelproviders"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXRerankers", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
    ]
)
