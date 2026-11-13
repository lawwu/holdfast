import Foundation

func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
    if !value() { throw NSError(domain: message, code: 1) }
}
final class Model: @unchecked Sendable {}
actor Gate {
    var continuation: CheckedContinuation<Void, Never>?
    var open = false
    func wait() async { if !open { await withCheckedContinuation { continuation = $0 } } }
    func release() { open = true; continuation?.resume(); continuation = nil }
}
@main struct LifecycleTests {
    @MainActor static func main() async throws {
        let domain = "architecture-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let queue = ModelDownloads(defaults: defaults)
        let first = Task {
            try await queue.run(id: "answer", name: "Answer", followUp: .selectAnswer) { _ in
                try await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
        while queue.item("answer")?.state != .downloading { await Task.yield() }
        queue.pause("answer")
        do { try await first.value; throw NSError(domain: "pause succeeded", code: 1) } catch is CancellationError {}
        var restored = 0
        let reopened = ModelDownloads(defaults: defaults, resolve: { _ in { _ in restored += 1 } })
        try check(reopened.item("answer")?.state == .paused, "restart must not auto-run")
        try check(reopened.item("answer")?.followUps == [.selectAnswer], "restart lost follow-up")
        reopened.resume("answer")
        while reopened.item("answer")?.state != .ready { await Task.yield() }
        try check(restored == 1, "restored operation did not run once")
        try check(reopened.item("answer")?.followUps == [.selectAnswer], "ready lost unaccepted action")
        reopened.deliverFollowUps { _, _ in false }
        try check(ModelDownloads(defaults: defaults).item("answer")?.followUps == [.selectAnswer], "busy caller lost action")
        reopened.deliverFollowUps { id, action in id == "answer" && action == .selectAnswer }
        try check(ModelDownloads(defaults: defaults).item("answer")?.followUps == [], "accepted action replayed")
        do {
            try await reopened.run(id: "bad", name: "Bad") { _ in throw NSError(domain: "validation", code: 1) }
        } catch {}
        try check(reopened.item("bad")?.state == .failed, "failed validation became ready")
        let cache = LoadedModel<Model>()
        let gate = Gate()
        let a = Task { try await cache.value(for: "a") { await gate.wait(); return Model() } }
        await Task.yield()
        let b = Task { try await cache.value(for: "a") { throw NSError(domain: "duplicate load", code: 1) } }
        // Allow both requests to reach the common loading task.
        try await Task.sleep(nanoseconds: 20_000_000)
        await gate.release()
        var firstModel: Model? = try await a.value
        var secondModel: Model? = try await b.value
        try check(firstModel === secondModel, "load was not coalesced")
        cache.unload()
        do { _ = try await cache.value(for: "b") { Model() }; throw NSError(domain: "switched during use", code: 1) } catch is LoadedModel<Model>.Busy {}
        firstModel = nil; secondModel = nil
        // The completed Tasks above still own their results, intentionally keeping the model in use.
        let staleCache = LoadedModel<Model>()
        let staleGate = Gate()
        let stale = Task { try await staleCache.value(for: "old") { await staleGate.wait(); return Model() } }
        try await Task.sleep(nanoseconds: 20_000_000)
        staleCache.unload()
        await staleGate.release()
        do { _ = try await stale.value; throw NSError(domain: "stale load accepted", code: 1) } catch is CancellationError {}
        try check(staleCache.loadedID == nil, "stale load repopulated cache")
        let releasedCache = LoadedModel<Model>()
        try await holdThenRelease(releasedCache)
        _ = try await releasedCache.value(for: "replacement") { Model() }
        try check(releasedCache.loadedID == "replacement", "released model blocked replacement")
        _ = try await releasedCache.value(for: "next") { Model() }
        try check(releasedCache.loadedID == "next", "idle cache could not switch models")
        let retryCache = LoadedModel<Model>()
        do { _ = try await retryCache.value(for: "retry") { throw NSError(domain: "load failed", code: 1) } } catch {}
        _ = try await retryCache.value(for: "retry") { Model() }
        try check(retryCache.loadedID == "retry", "failed load poisoned retry")
        print("PASS download restart, follow-up persistence, validation, coalesced loading, active use and stale-load refusal")
    }
    static func holdThenRelease(_ cache: LoadedModel<Model>) async throws {
        let held = try await cache.value(for: "held") { Model() }
        cache.unload()
        do { _ = try await cache.value(for: "replacement") { Model() }; throw NSError(domain: "active use lost", code: 1) }
        catch is LoadedModel<Model>.Busy {}
        withExtendedLifetime(held) {}
    }

}
