import Foundation
import ModelProviders

/// Endpoint-specific server profiles cannot accidentally change a local model's settings.
enum ModelPreferences {
    static func key(_ model: String, endpoint: String? = nil) -> String { "modelProfile.v1." + (endpoint.map { $0 + "|" } ?? "local|") + model }
    static func load(_ model: String, endpoint: String? = nil) -> ModelProfile {
        if let data = UserDefaults.standard.data(forKey: key(model, endpoint: endpoint)),
           let profile = try? JSONDecoder().decode(ModelProfile.self, from: data), var valid = try? profile.validated() {
            if ProcessInfo.processInfo.environment["HOLDFAST_THINK"] == "1" { valid.thinking = true }; return valid
        }
        var profile = ModelProfile.automatic(for: model)
        profile.thinking = UserDefaults.standard.bool(forKey: "showThinking") || ProcessInfo.processInfo.environment["HOLDFAST_THINK"] == "1"
        return profile
    }
    static func save(_ profile: ModelProfile, model: String, endpoint: String? = nil) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(profile.validated()), forKey: key(model, endpoint: endpoint))
    }
    static func reset(_ model: String, endpoint: String? = nil) { UserDefaults.standard.removeObject(forKey: key(model, endpoint: endpoint)) }
    static var selected: ModelProfile {
        if let kind = ProviderSettings.selected.serverKind {
            let c = ProviderSettings.current(kind)
            var profile = load(c.model, endpoint: c.baseURL)
            profile.contextTokens = min(profile.contextTokens, c.contextWindow)
            return profile
        }
        return load(MLXBackend.currentRepo)
    }
    static func setThinking(_ value: Bool) {
        let kind = ProviderSettings.selected.serverKind
        let c = kind.map(ProviderSettings.current)
        let model = c?.model ?? MLXBackend.currentRepo
        var profile = load(model, endpoint: c?.baseURL); profile.thinking = value
        try? save(profile, model: model, endpoint: c?.baseURL)
    }
}
