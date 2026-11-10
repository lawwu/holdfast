import Foundation

// Minimal app context for exercising production policy and migration without MLX.
enum Config {
    static var inPlace = true
    static let vault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}
struct Chunk { let relPath: String }

@main struct NamingMigrationTests {
    enum Failure: Error { case expectedFailure }

    static func main() throws {
        let root = "holdfast-migration-test-" + UUID().uuidString
        let old = root + "-old", older = root + "-older", current = root + "-current"
        let defaults = UserDefaults(suiteName: current)!
        defer { for name in [old, older, current] { defaults.removePersistentDomain(forName: name) } }
        defaults.setPersistentDomain(["backend": "custom", "searchByMeaning": false,
            "profile:/example": LegacyCompatibility.privateProfileID], forName: old)
        defaults.setPersistentDomain(["backend": "ollama", "rerankerOn": true], forName: older)
        defaults.set("mlx", forKey: "backend")
        Migrate.preferences(defaults, domains: [old, older])
        assert(defaults.string(forKey: "backend") == "mlx", "Current settings must win")
        assert(defaults.object(forKey: "searchByMeaning") as? Bool == false)
        assert(defaults.bool(forKey: "rerankerOn"))
        assert(defaults.string(forKey: "profile:/example") == "private")
        defaults.removeObject(forKey: "rerankerOn")
        Migrate.preferences(defaults, domains: [old, older])
        assert(defaults.object(forKey: "rerankerOn") == nil, "Migration only runs once")
        assert(LegacyCompatibility.preferenceDomains(app: true, bundle: "app.holdfast.pi-regular").first
            == LegacyCompatibility.previousBundleID + ".pi-regular")

        let key = "profile:" + Config.vault.path
        defer { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.set("general", forKey: key)
        for path in ["private/report.md", "confidential/report.md", LegacyCompatibility.privateProfileID + "/report.md"] {
            assert(Profile.isPrivate(path) && Profile.forPath(path) == .privateNotes)
        }
        assert(!Profile.isPrivate("finance/checklist.md"))
        assert(!Profile.isPrivateSource(URL(fileURLWithPath: "/private/tmp/ordinary.txt")))
        assert(Profile.isPrivateSource(URL(fileURLWithPath: "/private/tmp/private/record.txt")))
        assert(Profile.isPrivateSource(URL(fileURLWithPath: "/Users/example/confidential/record.txt")))
        UserDefaults.standard.set(LegacyCompatibility.privateProfileID, forKey: key)
        assert(Profile.vaultDefault == .privateNotes && Profile.isPrivate("finance/checklist.md"))
        UserDefaults.standard.removeObject(forKey: key)
        Config.inPlace = false
        assert(Profile.vaultDefault == .privateNotes)

        try FileManager.default.createDirectory(at: Config.vault.appendingPathComponent(LegacyCompatibility.stateFolder), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: Config.vault) }
        let payload = Data("saved proposal".utf8)
        try payload.write(to: Config.vault.appendingPathComponent(LegacyCompatibility.stateFolder + "/proposal"))
        Migrate.vaultState(Config.vault)
        let restored = try Data(contentsOf: Config.vault.appendingPathComponent(".holdfast/proposal"))
        assert(restored == payload)

        for suffix in ["model-servers", "model-downloads"] {
            let previous = LegacyCompatibility.previousBundleID + "." + suffix
            let next = "app.holdfast." + suffix
            var entries = [previous: "old-token"]
            func read() throws -> String? {
                try LegacyCompatibility.readCredential(suffix: suffix, read: { entries[$0] }, write: { entries[$1] = $0 })
            }
            let copied = try read()
            assert(copied == "old-token" && entries[next] == "old-token")
            entries[next] = "new-token"
            let preferred = try read()
            assert(preferred == "new-token", "Current credentials must win")
            try LegacyCompatibility.writeCredential(nil, suffix: suffix, write: { entries[$1] = $0 })
            let cleared = try read()
            assert(cleared == nil, "Cleared credentials must not return")
            entries[previous] = "keep-on-failure"
            do {
                _ = try LegacyCompatibility.readCredential(suffix: suffix, read: { entries[$0] }, write: { _, _ in throw Failure.expectedFailure })
                assertionFailure("Failed migration must be reported")
            } catch Failure.expectedFailure {}
            assert(entries[previous] == "keep-on-failure" && entries[next] == nil)
        }
        print("PASS: settings migration, protected profiles, saved vault state, credential copy/clear/failure")
    }
}
