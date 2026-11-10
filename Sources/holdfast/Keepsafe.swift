import CryptoKit
import Foundation

// MARK: - Keeping a family's records safe beyond this Mac
//
// - Backup: a dated copy of the vault and Holdfast's records for it, with a SHA-256 for every file,
//   then Verify (re-check every file) and Test Restore (restore into a temporary folder and open it).
// - Originals: the document a filing came from, kept in the vault beside its note and linked from it.
// - Export: chosen notes and their originals as a checked ZIP for a CPA, a doctor or an executor.
// - Pins: questions kept on the Ask home page.

/// SHA-256 of a file, read in chunks (originals can be large recordings).
func sha256(of url: URL) throws -> String {
    let h = try FileHandle(forReadingFrom: url)
    defer { try? h.close() }
    var hasher = SHA256()
    while let d = try h.read(upToCount: 1 << 20), !d.isEmpty { hasher.update(data: d) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

/// A checksum list: what a backup or an export holds.
struct Manifest: Codable {
    struct Entry: Codable { var path: String; var size: Int; var sha256: String }
    var created: Date
    var vault: String
    var holdfast: String
    var note: String
    var files: [Entry]

    static func read(_ url: URL) throws -> Manifest {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(Manifest.self, from: Data(contentsOf: url))
    }

    func write(_ url: URL) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url)
    }

    /// Every file under `root` checked against the list: missing, changed (size or hash) and extra files.
    func check(under root: URL) -> (ok: Int, missing: [String], changed: [String], extra: [String]) {
        var ok = 0, missing: [String] = [], changed: [String] = []
        for e in files {
            let u = root.appendingPathComponent(e.path)
            guard let size = (try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? Int else { missing.append(e.path); continue }
            if size != e.size || (try? sha256(of: u)) != e.sha256 { changed.append(e.path) } else { ok += 1 }
        }
        let listed = Set(files.map(\.path)).union(["manifest.json"])
        let extra = Keepsafe.files(under: root).map(\.rel).filter { !listed.contains($0) }
        return (ok, missing, changed, extra)
    }
}

enum Keepsafe {
    /// Folders never copied into a backup: git has its own history, the rest are caches or trash.
    static let skipped: Set<String> = [".git", "node_modules", ".trash", ".Trash"]

    /// Regular files under a folder, with paths relative to it (hidden files included: .holdfast state).
    static func files(under root: URL) -> [(url: URL, rel: String)] {
        let base = root.standardizedFileURL.path + "/"
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey]) else { return [] }
        var out: [(URL, String)] = []
        for case let u as URL in e {
            let v = try? u.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if v?.isDirectory == true, skipped.contains(u.lastPathComponent) { e.skipDescendants(); continue }
            guard v?.isRegularFile == true, u.lastPathComponent != ".DS_Store" else { continue }
            out.append((u, String(u.standardizedFileURL.path.dropFirst(base.count))))
        }
        return out.sorted { $0.1 < $1.1 }
    }

    /// A search index is a cache (rebuilt from the notes) and the write lock is only a lock: neither is backed up.
    static func isCache(_ rel: String) -> Bool {
        let name = (rel as NSString).lastPathComponent
        return (name.hasPrefix("index") && name.hasSuffix(".sqlite")) || name.hasPrefix("index") && name.contains(".sqlite-")
            || name == ".write.lock" || rel.hasPrefix("media/") || rel.contains("/media/")
    }
}

// MARK: backup

enum Backup {
    static var folderKey: String { "backupFolder" }
    /// Where backups go (chosen once in Settings, or given to the command).
    static var folder: URL? {
        get { UserDefaults.standard.string(forKey: folderKey).map { URL(fileURLWithPath: $0) } }
        set { UserDefaults.standard.set(newValue?.path, forKey: folderKey) }
    }

    struct Result {
        var folder: URL
        var files: Int
        var bytes: Int64
    }

    /// The backups of this vault in a folder, newest first.
    static func list(in dest: URL) -> [URL] {
        let prefix = "Holdfast \(Config.vault.lastPathComponent) "
        let items = (try? FileManager.default.contentsOfDirectory(at: dest, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.lastPathComponent.hasPrefix(prefix) && FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Copies the vault (without .git and caches), Holdfast's records for it (versions, filing log,
    /// history, kept originals, transcripts, rules; not the search index) and this app's settings into
    /// `dest/Holdfast <vault> <date time>/`, with a SHA-256 for every file in manifest.json.
    static func run(to dest: URL, progress: (Int, Int, String) -> Void = { _, _, _ in }) throws -> Result {
        let fm = FileManager.default
        let stamp = Versions.stamp.string(from: Date())
        let out = dest.appendingPathComponent("Holdfast \(Config.vault.lastPathComponent) \(stamp)")
        // Both folders exist before they're compared: macOS resolves /tmp vs /private/tmp only for existing paths.
        let existed = fm.fileExists(atPath: dest.path)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let vaultPath = Config.vault.resolvingSymlinksInPath().path + "/", destPath = dest.resolvingSymlinksInPath().path + "/"
        guard !destPath.hasPrefix(vaultPath) else {
            if !existed { try? fm.removeItem(at: dest) }
            throw HoldfastError("choose a backup folder outside the vault")
        }
        try fm.createDirectory(at: out, withIntermediateDirectories: true)
        var sources: [(from: URL, to: String)] = Keepsafe.files(under: Config.vault).compactMap { f in
            Keepsafe.isCache(f.rel) && f.rel.hasPrefix(".holdfast/") ? nil : (f.url, "vault/" + f.rel)
        }
        if Config.inPlace {  // the state folder lives in Application Support, not the vault
            sources += Keepsafe.files(under: Config.stateDir).compactMap { f in Keepsafe.isCache(f.rel) ? nil : (f.url, "state/" + f.rel) }
        }
        var entries: [Manifest.Entry] = []
        var bytes: Int64 = 0
        for (i, s) in sources.enumerated() {
            progress(i, sources.count, s.to)
            let to = out.appendingPathComponent(s.to)
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: s.from, to: to)
            let size = ((try? fm.attributesOfItem(atPath: to.path))?[.size] as? Int) ?? 0
            entries.append(.init(path: s.to, size: size, sha256: try sha256(of: to)))
            bytes += Int64(size)
        }
        // Settings (vault, model, backup folder…), so a restored Mac is set up the same way.
        if let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "holdfast"),
           let data = try? PropertyListSerialization.data(fromPropertyList: domain, format: .xml, options: 0) {
            let to = out.appendingPathComponent("settings.plist")
            try data.write(to: to)
            entries.append(.init(path: "settings.plist", size: data.count, sha256: try sha256(of: to)))
        }
        let readme = """
        A Holdfast backup of \(Config.vault.path), made \(stamp).

        vault/     the vault folder, without .git (git keeps its own history) and search indexes
        state/     Holdfast's records for it: versions, filing log, history, kept originals, transcripts, rules
        settings.plist   Holdfast's settings
        manifest.json    every file's size and SHA-256

        To restore: copy vault/ back into place, and state/ into ~/Library/Application Support/Holdfast/vaults/<vault>-<id>/
        (the folder name Holdfast uses for this vault). `holdfast backup --verify "<this folder>"` checks every file.

        """
        try readme.write(to: out.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        entries.append(.init(path: "README.txt", size: readme.utf8.count, sha256: try sha256(of: out.appendingPathComponent("README.txt"))))
        try Manifest(created: Date(), vault: Config.vault.path, holdfast: "0.1.0", note: "backup", files: entries)
            .write(out.appendingPathComponent("manifest.json"))
        progress(sources.count, sources.count, "done")
        UserDefaults.standard.set(Date(), forKey: "lastBackup:" + Config.vault.path)
        return Result(folder: out, files: entries.count, bytes: bytes)
    }

    /// Re-reads every file and compares it with the manifest.
    static func verify(_ backup: URL) throws -> String {
        let m = try Manifest.read(backup.appendingPathComponent("manifest.json"))
        let r = m.check(under: backup)
        if r.missing.isEmpty && r.changed.isEmpty {
            return "Verified: all \(r.ok) files match their checksums" + (r.extra.isEmpty ? "." : " (\(r.extra.count) files added since).")
        }
        return "Problems: \(r.missing.count) missing, \(r.changed.count) changed (of \(m.files.count)). "
            + (r.missing + r.changed).prefix(5).joined(separator: ", ")
    }

    /// Restores the backup into a temporary folder, checks every file there, opens every note and
    /// Holdfast's records, then removes the copy.
    static func testRestore(_ backup: URL) throws -> String {
        let fm = FileManager.default
        let m = try Manifest.read(backup.appendingPathComponent("manifest.json"))
        let tmp = fm.temporaryDirectory.appendingPathComponent("holdfast-restore-test-" + UUID().uuidString)
        defer { try? fm.removeItem(at: tmp) }
        try fm.copyItem(at: backup, to: tmp)
        let r = m.check(under: tmp)
        guard r.missing.isEmpty, r.changed.isEmpty else {
            return "Test restore failed: \(r.missing.count) files missing and \(r.changed.count) changed after restoring."
        }
        let notes = Keepsafe.files(under: tmp.appendingPathComponent("vault")).filter { $0.rel.hasSuffix(".md") && !$0.rel.hasPrefix(".") }
        var unreadable: [String] = []
        for n in notes where (try? Note.read(n.url)) == nil { unreadable.append(n.rel) }
        let state = tmp.appendingPathComponent(Config.inPlace ? "state" : "vault/.holdfast")
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let history = (try? Data(contentsOf: state.appendingPathComponent("history.json"))).flatMap { try? dec.decode([HistoryEntry].self, from: $0) }
        let filings = (try? Data(contentsOf: state.appendingPathComponent("filings.json"))).flatMap { try? dec.decode([FilingRecord].self, from: $0) }
        var s = "Test restore passed: \(r.ok) files restored and matched; \(notes.count - unreadable.count) of \(notes.count) notes open"
        if let history { s += "; \(history.count) saved answers" }
        if let filings { s += "; \(filings.count) filings in the log" }
        s += ". The temporary copy was removed."
        if !unreadable.isEmpty { s += " Notes that didn't open: " + unreadable.prefix(5).joined(separator: ", ") }
        return s
    }
}

// MARK: originals

enum Originals {
    /// Kept in the vault, in a folder git and the index skip (the -raw convention), beside the notes' folders.
    static let folder = "originals-raw"

    /// Copies a filing's original into originals-raw/<the note's folder>/ and returns its vault path,
    /// or nil when there is nothing to keep (no original, a text transcript, a CSV row).
    static func keep(original name: String?, for target: String) throws -> String? {
        guard Config.inPlace, let name, !name.isEmpty, !target.lowercased().hasSuffix(".csv") else { return nil }
        let ext = (name as NSString).pathExtension.lowercased()
        guard !["md", "markdown"].contains(ext) else { return nil }
        let src = Drop.filedDir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: src.path) else { return nil }
        let dir = (target as NSString).deletingLastPathComponent
        let root = Config.vault.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // The folder ignores itself, so originals never end up in the vault's git history.
        let ignore = root.appendingPathComponent(".gitignore")
        if !FileManager.default.fileExists(atPath: ignore.path) { try "*\n".write(to: ignore, atomically: true, encoding: .utf8) }
        let destDir = dir.isEmpty ? root : root.appendingPathComponent(dir)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        let dest = Drop.unique(destDir.appendingPathComponent(name), ifExists: true)
        try FileManager.default.copyItem(at: src, to: dest)
        return folder + "/" + (dir.isEmpty ? "" : dir + "/") + dest.lastPathComponent
    }

    /// The Markdown line that links a note at `notePath` to a kept original.
    static func link(_ kept: String, from notePath: String) -> String {
        let depth = notePath.split(separator: "/").count - 1
        let rel = String(repeating: "../", count: depth) + kept
        let href = rel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rel
        return "- [\((kept as NSString).lastPathComponent)](\(href)) · filed \(Drop.dayString(holdfast.today()))"
    }

    /// The originals a note links to, as files.
    static func linked(from note: Note) -> [URL] {
        let re = try! NSRegularExpression(pattern: #"\]\(([^)\s]*\#(folder)/[^)\s]+)\)"#)
        let ns = note.body as NSString
        return re.matches(in: note.body, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let raw = ns.substring(with: m.range(at: 1))
            let path = raw.removingPercentEncoding ?? raw
            let u = URL(fileURLWithPath: path, relativeTo: note.path.deletingLastPathComponent()).standardizedFileURL
            return FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
    }
}

// MARK: export

enum Export {
    struct Report {
        var zip: URL
        var notes: Int
        var originals: Int
        var leftOut: Int
        var verified: Bool
    }

    /// Notes for an export: those under `folder`, then those a search for `query` finds (best first).
    static func select(query: String, folder: String, notes: [Note], embedder: Embedder?) async -> [Note] {
        var picked: [Note] = []
        let f = folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if !f.isEmpty { picked += notes.filter { $0.relPath.hasPrefix(f + "/") || $0.relPath == f + ".md" } }
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty, let hits = try? await search(q, embedder: embedder, reranker: await Reranker.shared(), limit: 40, packs: false) {
            for h in hits { if let n = notes.first(where: { $0.relPath == h.relPath }), !picked.contains(where: { $0.path == n.path }) { picked.append(n) } }
        }
        return picked.filter { !$0.relPath.hasPrefix("@") }
    }

    /// The notes, the originals they link to, a README and manifest.json, zipped; then the ZIP is
    /// unpacked into a temporary folder and every file checked against the manifest.
    static func build(_ chosen: [Note], includePrivateNotes: Bool, title: String, to zip: URL) throws -> Report {
        let fm = FileManager.default
        let keep = chosen.filter { includePrivateNotes || !Profile.isPrivate($0.relPath) }
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Holdfast export" : title.replacingOccurrences(of: "/", with: "-")
        let stage = fm.temporaryDirectory.appendingPathComponent("holdfast-export-" + UUID().uuidString)
        defer { try? fm.removeItem(at: stage) }
        let root = stage.appendingPathComponent(name)
        var entries: [Manifest.Entry] = []
        func add(_ from: URL, as rel: String) throws {
            let to = root.appendingPathComponent(rel)
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !fm.fileExists(atPath: to.path) { try fm.copyItem(at: from, to: to) }
            let size = ((try? fm.attributesOfItem(atPath: to.path))?[.size] as? Int) ?? 0
            entries.append(.init(path: rel, size: size, sha256: try sha256(of: to)))
        }
        var originals = 0
        for n in keep {
            try add(n.path, as: n.relPath)
            for o in Originals.linked(from: n) {
                let rel = String(o.path.dropFirst(Config.vault.standardizedFileURL.path.count + 1))
                try add(o, as: rel)
                originals += 1
            }
        }
        let readme = """
        \(name)
        Exported from Holdfast on \(Drop.dayString(holdfast.today())): \(keep.count) notes and \(originals) original documents.
        Notes are Markdown files that open in any text editor; originals are under \(Originals.folder)/.
        manifest.json lists every file with its SHA-256, so the copy can be checked.
        \(chosen.count > keep.count ? "\(chosen.count - keep.count) private notes were left out.\n" : "")
        """
        try readme.write(to: root.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
        entries.append(.init(path: "README.txt", size: readme.utf8.count, sha256: try sha256(of: root.appendingPathComponent("README.txt"))))
        let manifest = Manifest(created: Date(), vault: Config.vault.lastPathComponent, holdfast: "0.1.0", note: "export: \(name)", files: entries)
        try manifest.write(root.appendingPathComponent("manifest.json"))
        if fm.fileExists(atPath: zip.path) { try fm.removeItem(at: zip) }
        // Plain ZIP: no macOS metadata (__MACOSX folders), so it opens cleanly on any computer.
        _ = try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--keepParent", root.path, zip.path])
        // Check the ZIP itself: unpack it and compare every file with the manifest.
        let check = fm.temporaryDirectory.appendingPathComponent("holdfast-export-check-" + UUID().uuidString)
        defer { try? fm.removeItem(at: check) }
        _ = try run("/usr/bin/ditto", ["-x", "-k", zip.path, check.path])
        let r = manifest.check(under: check.appendingPathComponent(name))
        return Report(zip: zip, notes: keep.count, originals: originals, leftOut: chosen.count - keep.count,
                      verified: r.missing.isEmpty && r.changed.isEmpty)
    }
}

// MARK: pins

struct Pin: Codable, Identifiable, Hashable {
    var question: String
    var id: String { question }
}

enum Pins {
    static var url: URL { Config.stateDir.appendingPathComponent("pinned.json") }
    static func load() -> [Pin] { (try? JSONDecoder().decode([Pin].self, from: Data(contentsOf: url))) ?? [] }
    static func save(_ ps: [Pin]) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(ps).write(to: url, options: .atomic)
    }
}
