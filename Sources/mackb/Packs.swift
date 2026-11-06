import Foundation

// MARK: - Knowledge packs
//
// Read-only reference collections that sit beside the vault: a Bible, a wiki,
// a manual. Each pack is a folder of Markdown notes with a manifest
// (packs/<id>/pack.json) and its own search index, shared by every vault.
// Search and Ask draw on the packs that are switched on, and their passages are
// cited as "pack:<id>/…" so an answer never mixes them up with your own notes.
// Nothing in a pack is edited, filed into, or synced.

struct PackManifest: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var version: String
    /// The license, as the source states it; packs are only built from text that allows this use.
    var license: String
    var attribution: String
    var source: String
    var description: String
    /// Short label used in citations, e.g. "BSB".
    var cite: String
}

enum Packs {
    /// Shared by all vaults.
    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacKB/packs")
    }
    static let prefix = "pack:"

    static func folder(_ id: String) -> URL { dir.appendingPathComponent(id) }
    static func notesDir(_ id: String) -> URL { folder(id).appendingPathComponent("notes") }
    static func indexPath(_ id: String) -> URL { folder(id).appendingPathComponent(Config.indexPath.lastPathComponent) }

    static func installed() -> [PackManifest] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.compactMap { u in
            (try? Data(contentsOf: u.appendingPathComponent("pack.json"))).flatMap { try? JSONDecoder().decode(PackManifest.self, from: $0) }
        }.sorted { $0.name < $1.name }
    }

    // MARK: on / off

    static var enabledURL: URL { dir.appendingPathComponent("enabled.json") }

    /// Packs Search and Ask use. MACKB_PACKS=id,id (or "none") overrides, for evals and the CLI.
    static func enabled() -> Set<String> {
        if let env = ProcessInfo.processInfo.environment["MACKB_PACKS"] {
            return env == "none" ? [] : Set(env.split(separator: ",").map(String.init))
        }
        guard let d = try? Data(contentsOf: enabledURL), let ids = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return Set(ids)
    }

    static func setEnabled(_ id: String, _ on: Bool) {
        var s = enabled()
        if on { s.insert(id) } else { s.remove(id) }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(s.sorted()).write(to: enabledURL, options: .atomic)
    }

    /// Enabled packs that have an index to search.
    static func searchable() -> [String] {
        enabled().filter { FileManager.default.fileExists(atPath: indexPath($0).path) }.sorted()
    }

    // MARK: notes

    static func notes(_ id: String) -> [Note] { allNotes(in: [notesDir(id)]) }

    static func isPack(_ relPath: String) -> Bool { relPath.hasPrefix(prefix) }

    /// The pack id of a "pack:<id>/…" path.
    static func id(of relPath: String) -> String? {
        guard isPack(relPath) else { return nil }
        return relPath.dropFirst(prefix.count).split(separator: "/").first.map(String.init)
    }

    /// The note at a "pack:<id>/…" path.
    static func note(_ relPath: String) -> Note? {
        guard let id = id(of: relPath) else { return nil }
        // "pack:bsb/notes/43 John/John 3": the path under the pack's folder.
        var rest = String(relPath.dropFirst(prefix.count + id.count + 1))
        if let hash = rest.firstIndex(of: "#") { rest = String(rest[..<hash]) }
        return try? Note.read(folder(id).appendingPathComponent(rest.hasSuffix(".md") ? rest : rest + ".md"))
    }

    static func manifest(_ id: String) -> PackManifest? { installed().first { $0.id == id } }

    // MARK: install and index

    /// Copies a built pack folder (pack.json + notes/) into place.
    @discardableResult
    static func install(from src: URL) throws -> PackManifest {
        let m = try JSONDecoder().decode(PackManifest.self, from: Data(contentsOf: src.appendingPathComponent("pack.json")))
        let dest = folder(m.id)
        guard src.standardizedFileURL != dest.standardizedFileURL else { return m }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.copyItem(at: src, to: dest)
        return m
    }

    static func remove(_ id: String) throws {
        setEnabled(id, false)
        try FileManager.default.trashItem(at: folder(id), resultingItemURL: nil)
    }

    static func reindex(_ id: String, embedder: Embedder?, force: Bool = false) async throws {
        try await reindexNotes(Index(path: indexPath(id)), notes: notes(id), embedder: embedder, force: force)
    }

    static func count(_ id: String) -> (chunks: Int, notes: Int, vectors: Int)? {
        guard FileManager.default.fileExists(atPath: indexPath(id).path) else { return nil }
        return (try? Index(path: indexPath(id)))?.count()
    }

    /// A pack made from a folder of files (saved web pages, PDFs, Markdown…), converted
    /// the way "Bring in as-is" converts them. For text the license lets you keep.
    static func create(id: String, name: String, license: String, attribution: String, source: String,
                       description: String, cite: String, from sources: [URL]) async throws -> BulkImport.Report {
        let m = PackManifest(id: id, name: name, version: Drop.dayString(mackb.today()), license: license, attribution: attribution,
                             source: source, description: description, cite: cite)
        try FileManager.default.createDirectory(at: folder(id), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(m).write(to: folder(id).appendingPathComponent("pack.json"))
        return await BulkImport.asIs(sources, into: "notes", root: folder(id), keepOriginals: false) { _, _, _ in }
    }
}
