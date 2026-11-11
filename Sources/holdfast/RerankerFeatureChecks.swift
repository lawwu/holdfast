#if HOLDFAST_DEMO_CAPTURE
import Foundation

/// Real MLX checks, opt-in and restricted to the isolated sample-vault app.
@MainActor enum RerankerFeatureChecks {
    static func run(store: Store) async throws -> [String] {
        guard (try? String(contentsOf: store.vault.appendingPathComponent(".holdfast-demo"), encoding: .utf8)) == "public sample notes only\n",
              store.canChangeReranker, !RerankerPreferences.hasModelOverride, !RerankerPreferences.disabledForLaunch else {
            throw HoldfastError("Use an idle sample-vault app with no reranker launch override.")
        }
        let original = store.rerankerModel, wasEnabled = store.rerankerOn, meaning = store.searchByMeaning
        defer {
            store.busy = nil
            store.selectReranker(original); store.setRerankerEnabled(wasEnabled)
            Reranker.unload()
        }
        var passed: [String] = []
        for choice in RerankerModel.allCases {
            guard RerankerDownloadControls.isAvailable(choice.id) else { throw HoldfastError("Download \(choice.name) before running the live check") }
            store.selectReranker(choice); store.setRerankerEnabled(true)
            guard Reranker.loadedRepo == nil, RerankerPreferences.saved() == choice else { throw HoldfastError("Model switch did not unload and persist the choice") }
            store.busy = "Checking \(choice.name)…"
            // A second request while the first is loading must use the same allocation.
            async let first = Reranker.shared()
            async let second = Reranker.shared()
            guard let a = await first, let b = await second, a === b, Reranker.loadedRepo == choice.id else {
                throw HoldfastError("Failed to load or coalesce \(choice.name): \(Reranker.loadError ?? "unknown error")")
            }
            let scores = try await a.score(query: "When does the train leave on Saturday?", documents: [
                "The train leaves at 9:15 on Saturday morning.",
                "Mix two cups of flour and bake the banana bread for an hour."
            ])
            guard scores.count == 2, scores.allSatisfy({ $0.isFinite && (0...1).contains($0) }), scores[0] > scores[1] else {
                throw HoldfastError("Unexpected relevance scores for \(choice.name): \(scores)")
            }
            store.selectReranker(choice == .small ? .medium : .small)
            guard store.rerankerModel == choice else { throw HoldfastError("A busy reranker was allowed to change") }
            store.busy = nil
            store.setRerankerEnabled(false)
            guard Reranker.loadedRepo == nil, await Reranker.shared() == nil, store.rerankerModel == choice,
                  store.searchByMeaning == meaning else { throw HoldfastError("Off did not release memory or altered other preferences") }
            passed.append("\(choice.name): correct relevance order, shared load, safe switch, persisted choice, Off releases memory")
        }
        return passed
    }
}
#endif
