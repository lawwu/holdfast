import Foundation

// MARK: - From the old name
//
// Holdfast was called mackb (MacKB) as a proof of concept. On the first run under the new name,
// what was kept under the old one moves over, so nothing has to be set up again:
// - the app-wide folder ~/Library/Application Support/MacKB (vault state, packs, models) → Holdfast
// - saved settings (the app's net.lawrencewu.mackb domain, the command line's "mackb") → this one's
// - MACKB_* environment variables still work, as HOLDFAST_*
// - a managed vault's hidden .mackb folder becomes .holdfast when the vault is opened
// - a default vault at ~/MacKB keeps being used while there is no ~/Holdfast

enum Migrate {
    static let oldFolder = "MacKB", oldCLIDomain = "mackb", oldBundle = "net.lawrencewu.mackb", oldState = ".mackb"

    static func fromOldName(app: Bool) {
        let fm = FileManager.default
        let support = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let old = support.appendingPathComponent(oldFolder), new = support.appendingPathComponent("Holdfast")
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) { try? fm.moveItem(at: old, to: new) }
        let d = UserDefaults.standard
        if !d.bool(forKey: "migratedFromMacKB") {
            for (k, v) in d.persistentDomain(forName: app ? oldBundle : oldCLIDomain) ?? [:] where d.object(forKey: k) == nil {
                d.set(v, forKey: k)
            }
            d.set(true, forKey: "migratedFromMacKB")
        }
        let env = ProcessInfo.processInfo.environment
        for (k, v) in env where k.hasPrefix("MACKB_") {
            let name = "HOLDFAST_" + k.dropFirst("MACKB_".count)
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
