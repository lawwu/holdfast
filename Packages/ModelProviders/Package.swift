// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ModelProviders",
    platforms: [.macOS(.v15)],
    products: [.library(name: "ModelProviders", targets: ["ModelProviders"])],
    targets: [
        .target(name: "ModelProviders", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
