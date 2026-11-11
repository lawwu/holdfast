#if HOLDFAST_DEMO_CAPTURE
import Foundation
import ModelProviders

/// Integration checks compiled only into the sample-vault app, never a release.
@MainActor enum ModelFeatureChecks {
    static func run(store: Store) async throws -> [String] {
        guard (try? String(contentsOf: Config.vault.appendingPathComponent(".holdfast-demo"), encoding: .utf8)) == "public sample notes only\n" else { throw HoldfastError("A sample vault is required") }
        func check(_ value: @autoclosure () throws -> Bool, _ message: String) throws { if try !value() { throw HoldfastError(message) } }
        var passed: [String] = []
        let name = "app.holdfast.feature-checks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let queue = ModelDownloads(defaults: defaults)
        var active = 0; var peak = 0; var order: [String] = []
        let first = Task {
            try await queue.run(id: "first", name: "First") { _ in
                active += 1; peak = max(peak, active); order.append("first")
                defer { active -= 1 }
                try await Task.sleep(for: .seconds(30))
            }
        }
        try await Task.sleep(for: .milliseconds(30))
        let second = Task {
            try await queue.run(id: "second", name: "Second") { _ in
                active += 1; peak = max(peak, active); order.append("second")
                defer { active -= 1 }; try await Task.sleep(for: .milliseconds(40))
            }
        }
        try await Task.sleep(for: .milliseconds(30))
        try check(queue.item("second")?.state == .queued, "Second download did not queue")
        queue.pause("first")
        do { try await first.value; throw HoldfastError("Paused job completed successfully") } catch is CancellationError {}
        try await second.value
        try check(peak == 1 && order == ["first", "second"], "Downloads ran concurrently")
        try check(queue.item("first")?.state == .paused && queue.item("second")?.state == .ready, "Queue states are wrong")
        let reopened = ModelDownloads(defaults: defaults)
        try check(reopened.item("first")?.state == .paused, "Paused state did not survive relaunch")
        passed.append("Download queue serializes transfers, cancels safely, persists paused jobs")

        var attempts = 0
        do {
            try await queue.run(id: "retry", name: "Retry") { _ in
                attempts += 1
                if attempts == 1 { throw HoldfastError("Temporary test failure") }
            }
        } catch {}
        queue.resume("retry", store: store)
        for _ in 0..<50 { if queue.item("retry")?.state == .ready { break }; try await Task.sleep(for: .milliseconds(20)) }
        try check(attempts == 2 && queue.item("retry")?.state == .ready, "Retry did not reuse the operation")
        passed.append("Failed downloads retry")

        let modelID = "test/profile-" + UUID().uuidString
        let endpoint = "http://127.0.0.1:1"
        defer { ModelPreferences.reset(modelID); ModelPreferences.reset(modelID, endpoint: endpoint) }
        var profile = ModelProfile.automatic(for: modelID)
        profile.maxOutputTokens = 512; profile.thinking = true
        try ModelPreferences.save(profile, model: modelID)
        try check(ModelPreferences.load(modelID) == profile, "Local profile did not persist")
        try check(ModelPreferences.load(modelID, endpoint: endpoint) != profile, "Local profile leaked into server settings")
        var serverProfile = profile; serverProfile.temperature = 0.2
        try ModelPreferences.save(serverProfile, model: modelID, endpoint: endpoint)
        try check(ModelPreferences.load(modelID) == profile && ModelPreferences.load(modelID, endpoint: endpoint) == serverProfile, "Endpoint profiles are not independent")
        var invalid = profile; invalid.maxOutputTokens = 0
        do { try ModelPreferences.save(invalid, model: modelID); throw HoldfastError("Invalid profile saved") }
        catch { try check(ModelPreferences.load(modelID) == profile, "Invalid profile replaced valid settings") }
        passed.append("Per-model settings persist and stay separate from endpoint profiles")

        let path = "comparison-feature-check.md"
        let url = Config.vault.appendingPathComponent(path)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw HoldfastError("Test note already exists") }
        let original = "# Test checklist\n\n- [ ] Pack the blue notebook\n"
        let data = Data(original.utf8)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let hits = [Chunk(noteId: "test", relPath: path, title: "Test checklist", anchor: "Test checklist", text: original)]
        let snapshot = try ComparisonSnapshot(question: "Mark the blue notebook done", passages: hits)
        let arguments = ["path": path, "old_text": "- [ ] Pack the blue notebook", "new_text": "- [x] Pack the blue notebook"]
        let call = AgentRuntime.Call(id: "test-call", name: "propose_edit", arguments: String(decoding: try JSONEncoder().encode(arguments), as: UTF8.self))
        let beforeCount = inbox().count
        let previews = try ComparisonPreview.edits([call], snapshot: snapshot)
        try check(previews.count == 1 && previews[0].proposed.contains("[x]"), "Comparison did not preview the edit")
        try check(try Data(contentsOf: url) == data && inbox().count == beforeCount, "Preview changed files or Inbox")
        var outside = arguments; outside["path"] = "../outside.md"
        let bad = AgentRuntime.Call(id: "bad", name: "propose_edit", arguments: String(decoding: try JSONEncoder().encode(outside), as: UTF8.self))
        do { _ = try ComparisonPreview.edits([bad], snapshot: snapshot); throw HoldfastError("Outside-snapshot edit accepted") }
        catch { try check(error.localizedDescription.contains("outside the frozen snapshot"), "Wrong out-of-snapshot failure") }
        let preview = previews[0]
        try Data((original + "Changed by hand\n").utf8).write(to: url)
        do {
            try Edits.propose(path: path, old: original, new: preview.proposed, why: "Test", by: "Test", expectedBytesHash: preview.bytesHash)
            throw HoldfastError("Stale comparison was accepted")
        } catch { try check(error.localizedDescription.contains("changed since the comparison"), "Wrong stale-comparison failure") }
        try check(snapshot.documents[path]?.text == original, "Snapshot changed with the file")
        try data.write(to: url)
        try Edits.propose(path: path, old: original, new: preview.proposed, why: "Test", by: "Test", expectedBytesHash: preview.bytesHash)
        guard let proposal = Edits.pending(for: path) else { throw HoldfastError("Missing Inbox proposal") }
        defer { try? FileManager.default.removeItem(at: proposal.path) }
        try check(try Data(contentsOf: url) == data, "Sending to Inbox edited the original")
        passed.append("Comparisons freeze references, reject outside/stale edits, and only queue chosen previews")

        let attachment = ChatAttachment(id: UUID(), url: URL(fileURLWithPath: "/tmp/sample.txt"), text: "Reference-only content", loading: false)
        let rendered = AttachmentContext.render([attachment])
        try check(rendered.contains("A1") && rendered.contains("Reference-only content") && !rendered.contains("/tmp/sample.txt"), "Attachment context leaked source path")
        let privateSnapshot = try ComparisonSnapshot(question: "Summarize", passages: [], attachments: rendered)
        try check(privateSnapshot.localOnly, "Attachment comparison was not local-only")
        passed.append("Attachments exclude original paths and force local-only comparison")
        return passed
    }
}
#endif
