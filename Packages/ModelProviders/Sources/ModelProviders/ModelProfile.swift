import Foundation

/// Portable, explicit inference preferences. Apps own persistence and the model catalog.
public struct ModelProfile: Codable, Sendable, Equatable {
    public var contextTokens: Int
    public var maxOutputTokens: Int
    public var temperature: Float
    public var topP: Float
    public var topK: Int
    public var presencePenalty: Float
    public var thinking: Bool

    public init(contextTokens: Int = 32768, maxOutputTokens: Int = 2000, temperature: Float = 0.7,
                topP: Float = 0.9, topK: Int = 40, presencePenalty: Float = 0, thinking: Bool = false) {
        self.contextTokens = contextTokens; self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature; self.topP = topP; self.topK = topK
        self.presencePenalty = presencePenalty; self.thinking = thinking
    }

    /// Conservative app defaults, not claims about a model's maximum supported context.
    public static func automatic(for model: String) -> Self {
        if model.lowercased().contains("qwen") {
            return .init(topP: 0.8, topK: 20, presencePenalty: 1.5)
        }
        if model.lowercased().contains("gemma") { return .init(temperature: 0.7, topP: 0.95, topK: 64) }
        return .init()
    }

    public func validated() throws -> Self {
        guard (4096...131072).contains(contextTokens), (128...16384).contains(maxOutputTokens),
              maxOutputTokens < contextTokens / 2, temperature.isFinite, (0...2).contains(temperature),
              topP.isFinite, (0.01...1).contains(topP), (0...1000).contains(topK),
              presencePenalty.isFinite, (0...2).contains(presencePenalty) else {
            throw Inference.Failure("Check the model settings. The output limit must be less than half the context limit.")
        }
        return self
    }

    public var generation: Inference.Generation {
        .init(maxTokens: maxOutputTokens, temperature: temperature, topP: topP, topK: topK, presencePenalty: presencePenalty)
    }
    public var templateContext: [String: any Sendable] {
        ["enable_thinking": thinking, "reasoning_effort": thinking ? "medium" : "low"]
    }
}

/// Group precision variants without conflating parameter counts or model generations.
public enum ModelIdentity {
    public static func family(_ id: String) -> String {
        let name = id.split(separator: "/").last.map(String.init) ?? id
        return name.replacingOccurrences(of: #"(?i)[-_](?:\d+(?:\.\d+)?[-_]?bit|bf16|fp16)(?:[-_]mlx)?$"#,
                                         with: "", options: .regularExpression)
    }
    public static func precision(_ id: String) -> String? {
        let pattern = #"(?i)(\d+(?:\.\d+)?)[-_]?bit|bf16|fp16"#
        guard let range = id.range(of: pattern, options: .regularExpression) else { return nil }
        return String(id[range]).lowercased().replacingOccurrences(of: "bit", with: "-bit").replacingOccurrences(of: "--", with: "-")
    }
}
