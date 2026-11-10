import Foundation

// Move earlier installations' data and settings without replacing current choices.

enum Migrate {
    static let oldFolder = LegacyCompatibility.dataFolder, oldState = LegacyCompatibility.stateFolder

    static func preferences(_ defaults: UserDefaults, domains: [String]) {
        guard !defaults.bool(forKey: "migratedAppIdentityV2") else { return }
        for domain in domains {
            for (key, value) in defaults.persistentDomain(forName: domain) ?? [:] where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix("profile:") {
            if let id = value as? String, let migrated = LegacyCompatibility.profileID(id), migrated != id {
                defaults.set(migrated, forKey: key)
            }
        }
        defaults.set(true, forKey: "migratedAppIdentityV2")
    }

    static func fromOldName(app: Bool) {
        let fm = FileManager.default
        let support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let old = support.appendingPathComponent(oldFolder), new = support.appendingPathComponent("Holdfast")
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) { try? fm.moveItem(at: old, to: new) }
        preferences(.standard, domains: LegacyCompatibility.preferenceDomains(app: app, bundle: Bundle.main.bundleIdentifier))
        let env = ProcessInfo.processInfo.environment
        for (k, v) in env where k.hasPrefix(LegacyCompatibility.environmentPrefix) {
            let name = "HOLDFAST_" + k.dropFirst(LegacyCompatibility.environmentPrefix.count)
            if env[name] == nil { setenv(name, v, 0) }
        }
    }

    static func defaultVault() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let new = home.appendingPathComponent("Holdfast"), old = home.appendingPathComponent(oldFolder)
        let fm = FileManager.default
        return !fm.fileExists(atPath: new.path) && fm.fileExists(atPath: old.path) ? old : new
    }

    /// A managed vault's state folder under its old name.
    static func vaultState(_ vault: URL) {
        let old = vault.appendingPathComponent(oldState), new = vault.appendingPathComponent(".holdfast")
        let fm = FileManager.default
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) { try? fm.moveItem(at: old, to: new) }
    }
}
