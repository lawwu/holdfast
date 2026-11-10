// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "LocalMLX",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "LocalMLX", targets: ["LocalMLX"]),
        .executable(name: "local-mlx-host", targets: ["LocalMLXHost"]),
    ],
    dependencies: [
        .package(path: "../ModelProviders"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "LocalMLX", dependencies: [.product(name: "ModelProviders", package: "modelproviders"),
                                                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                                                .product(name: "MLXLLM", package: "mlx-swift-lm")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "LocalMLXHost", dependencies: ["LocalMLX",
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
            .product(name: "Tokenizers", package: "swift-transformers"),
        ], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
