import Foundation

/// Reranker checkpoints supported by the app's pinned MLXRerankers runtime.
/// These are separate from answer models and never require rebuilding an index.
enum RerankerModel: String, CaseIterable, Identifiable, Sendable {
    case small = "mlx-community/Qwen3-Reranker-0.6B-4bit"
    case medium = "mlx-community/Qwen3-Reranker-4B-mxfp8"
    case large = "galaxycore/Qwen3-Reranker-8B-MLX-4bit"

    var id: String { rawValue }
    var name: String {
        switch self {
        case .small: return "Qwen3 Reranker 0.6B"
        case .medium: return "Qwen3 Reranker 4B"
        case .large: return "Qwen3 Reranker 8B"
        }
    }
    var menuLabel: String { name + (self == .small ? " · Recommended" : "") }
    var precision: String { self == .medium ? "MXFP8" : "4-bit" }
    /// Selected model files, rounded from the checkpoint manifests (November 2026).
    var downloadGB: Double {
        switch self { case .small: return 0.35; case .medium: return 4.2; case .large: return 4.6 }
    }
    /// A rough allowance in addition to the answer and embedding models, not a benchmark.
    var memoryGB: Double {
        switch self { case .small: return 2; case .medium: return 6; case .large: return 8 }
    }
    var detail: String {
        switch self {
        case .small: return "Recommended for everyday search. Smallest download and fastest of these choices."
        case .medium: return "Try for harder searches. Larger and slower; improvements depend on your notes."
        case .large: return "Largest option. Uses the most memory and takes longer; not yet benchmarked on Holdfast's full search evaluation."
        }
    }
    var sizeLabel: String {
        self == .small ? "About 350 MB download" : String(format: "About %.1f GB download", downloadGB)
    }
}

enum RerankerPreferences {
    static let key = "rerankerModel"
    static func saved(defaults: UserDefaults = .standard) -> RerankerModel {
        defaults.string(forKey: key).flatMap(RerankerModel.init(rawValue:)) ?? .small
    }
    static func save(_ model: RerankerModel, defaults: UserDefaults = .standard) { defaults.set(model.rawValue, forKey: key) }
    static func repo(defaults: UserDefaults = .standard, environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        override(environment["HOLDFAST_RERANK_REPO"]) ?? saved(defaults: defaults).rawValue
    }
    static func override(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
    static var hasModelOverride: Bool {
        let env = ProcessInfo.processInfo.environment
        return override(env["HOLDFAST_RERANK_REPO"]) != nil || override(env["HOLDFAST_RERANK_DIR"]) != nil
    }
    static var disabledForLaunch: Bool { ProcessInfo.processInfo.environment["HOLDFAST_RERANK"] == "0" }
}
