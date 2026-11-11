import Foundation

@main struct RerankerPreferencesTests {
    static func main() throws {
        let domain = "app.holdfast.reranker-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        precondition(RerankerPreferences.saved(defaults: defaults) == .small)
        precondition(RerankerPreferences.repo(defaults: defaults, environment: [:]) == RerankerModel.small.id)
        defaults.set(false, forKey: "searchByMeaning")
        defaults.set(false, forKey: "rerankerOn")
        RerankerPreferences.save(.medium, defaults: defaults)
        precondition(RerankerPreferences.saved(defaults: UserDefaults(suiteName: domain)!) == .medium)
        precondition(RerankerPreferences.repo(defaults: defaults, environment: [:]) == RerankerModel.medium.id)
        precondition(!defaults.bool(forKey: "searchByMeaning") && !defaults.bool(forKey: "rerankerOn"), "Choosing a model must not turn on search or reranking")
        let custom = "example/custom-reranker"
        precondition(RerankerPreferences.repo(defaults: defaults, environment: ["HOLDFAST_RERANK_REPO": custom]) == custom)
        precondition(RerankerPreferences.saved(defaults: defaults) == .medium, "Launch override must not overwrite saved selection")
        precondition(RerankerPreferences.repo(defaults: defaults, environment: ["HOLDFAST_RERANK_REPO": " \n"]) == RerankerModel.medium.id)
        defaults.set("removed-or-invalid-model", forKey: RerankerPreferences.key)
        precondition(RerankerPreferences.saved(defaults: defaults) == .small)
        precondition(Set(RerankerModel.allCases.map(\.id)).count == 3)
        for model in RerankerModel.allCases {
            precondition(model.id.contains("Reranker") && model.memoryGB > model.downloadGB)
        }
        print("PASS: reranker defaults, persistent choice, independent toggles, override precedence and invalid preference recovery")
    }
}
