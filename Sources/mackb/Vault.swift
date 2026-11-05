import Foundation

struct Segment {
    var start: Double
    var text: String
}

func formatTime(_ t: Double) -> String {
    let s = Int(t.rounded(.down))
    return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
}

func parseTime(_ s: String) -> Double? {
    let p = s.split(separator: ":").compactMap { Double($0) }
    guard p.count == 3 else { return nil }
    return p[0] * 3600 + p[1] * 60 + p[2]
}

func slugify(_ s: String) -> String {
    let allowed = CharacterSet.alphanumerics
    let words = s.lowercased().components(separatedBy: allowed.inverted).filter { !$0.isEmpty }
    return String(words.prefix(10).joined(separator: "-").prefix(80))
}

/// A note in the vault: YAML frontmatter + Markdown body.
struct Note {
    var path: URL
    var meta: [String: String]
    var body: String

    /// The vault-relative path without ".md": unique, unlike the file name
    /// (an in-place vault has a README.md in every folder).
    var id: String { String(relPath.dropLast(relPath.hasSuffix(".md") ? 3 : 0)) }
    /// The file name without ".md".
    var name: String { path.deletingPathExtension().lastPathComponent }
    /// Frontmatter title, else the first H1, else the file name; a bare
    /// "README" becomes its folder's name.
    var title: String {
        if let t = meta["title"] { return t }
        if let h = body.split(separator: "\n").first(where: { $0.hasPrefix("# ") }) {
            return h.dropFirst(2).trimmingCharacters(in: .whitespaces)
        }
        if name.lowercased() == "readme" { return path.deletingLastPathComponent().lastPathComponent }
        return name
    }
    /// Path relative to the vault; files kept in an in-place vault's state
    /// folder (imports, memories, inbox) are shown as "@sources/…" etc.
    var relPath: String {
        let p = path.standardizedFileURL.path
        for (root, prefix) in [(Config.vault, ""), (Config.stateDir, "@")] {
            let r = root.standardizedFileURL.path + "/"
            if p.hasPrefix(r) { return prefix + String(p.dropFirst(r.count)) }
        }
        return p
    }
    /// Top-level folder, e.g. "health" for health/goals.md; nil at the root.
    var domain: String? {
        let parts = relPath.split(separator: "/")
        return parts.count > 1 && !relPath.hasPrefix("@") ? String(parts[0]) : nil
    }

    static func read(_ url: URL) throws -> Note {
        let text = try String(contentsOf: url, encoding: .utf8)
        var meta: [String: String] = [:]
        var body = text
        if text.hasPrefix("---\n"), let end = text.range(of: "\n---\n", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) {
            let fm = text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound]
            for line in fm.split(separator: "\n") {
                guard let c = line.firstIndex(of: ":") else { continue }
                let k = line[..<c].trimmingCharacters(in: .whitespaces)
                var v = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
                meta[k] = v
            }
            body = String(text[end.upperBound...])
        }
        return Note(path: url, meta: meta, body: body)
    }

    func write() throws {
        var out = "---\n"
        for k in meta.keys.sorted() {
            let v = meta[k]!.replacingOccurrences(of: "\"", with: "'")
            out += "\(k): \"\(v)\"\n"
        }
        out += "---\n" + body
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try out.write(to: path, atomically: true, encoding: .utf8)
    }

    /// Transcript segments, from lines shaped `[hh:mm:ss] text`.
    var segments: [Segment] {
        body.split(separator: "\n").compactMap { line -> Segment? in
            guard line.hasPrefix("["), line.count > 11 else { return nil }
            let ts = String(line.dropFirst().prefix(8))
            guard line.dropFirst(9).first == "]", let t = parseTime(ts) else { return nil }
            return Segment(start: t, text: line.dropFirst(10).trimmingCharacters(in: .whitespaces))
        }
    }
}

/// Every note the index covers: the vault's own Markdown (in place) plus
/// imports and approved memories.
func allNotes() -> [Note] {
    var out = Config.inPlace ? vaultMarkdown().compactMap { try? Note.read($0) } : []
    out += allNotes(in: [Config.sourcesDir, Config.memoryDir])
    return out.sorted { $0.relPath < $1.relPath }
}

/// Folders never indexed in an in-place vault: raw exports, dependencies.
let skippedFolders = ["node_modules", ".git", ".obsidian", ".trash"]

/// Markdown files in an in-place vault. In a git repo, what git tracks or
/// would track (so .gitignore'd raw exports stay out); elsewhere, a walk that
/// skips hidden folders. Folders ending in "-raw" are skipped either way.
func vaultMarkdown() -> [URL] { vaultFiles(ext: "md") }

/// Files with this extension in an in-place vault. Inside a git work tree
/// (the vault folder or any parent is a repo), what git tracks or would track,
/// so .gitignore'd raw exports stay out; otherwise a walk that skips hidden
/// folders. Folders ending in "-raw" are skipped either way.
func vaultFiles(ext: String) -> [URL] {
    let root = Config.vault
    func keep(_ rel: String) -> Bool {
        !rel.split(separator: "/").dropLast().contains { $0.hasPrefix(".") || $0.hasSuffix("-raw") || skippedFolders.contains(String($0)) }
    }
    if (try? run("/usr/bin/git", ["-C", root.path, "rev-parse", "--is-inside-work-tree"]))?.hasPrefix("true") == true,
       let list = try? run("/usr/bin/git", ["-C", root.path, "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "*.\(ext)"]) {
        return list.split(separator: "\0").map(String.init).filter(keep).map { root.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
    var out: [URL] = []
    guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
    for case let u as URL in e {
        let rel = String(u.path.dropFirst(root.path.count + 1))
        if u.hasDirectoryPath, !keep(rel + "/x") { e.skipDescendants(); continue }
        if u.pathExtension.lowercased() == ext { out.append(u) }
    }
    return out
}

func allNotes(in dirs: [URL]) -> [Note] {
    var out: [Note] = []
    for d in dirs {
        guard let e = FileManager.default.enumerator(at: d, includingPropertiesForKeys: nil) else { continue }
        for case let u as URL in e where u.pathExtension == "md" {
            if let n = try? Note.read(u) { out.append(n) }
        }
    }
    return out.sorted { $0.path.path < $1.path.path }
}

/// Look a note up by id ("health/goals"), vault path ("health/goals.md"),
/// or bare file name ("goals", as older ids and history entries used).
func findNote(_ idOrPath: String) -> Note? {
    let key = idOrPath.hasSuffix(".md") ? String(idOrPath.dropLast(3)) : idOrPath
    let notes = allNotes() + allNotes(in: [Config.inboxDir])
    return notes.first { $0.id == key } ?? notes.first { $0.name == key }
}

func transcriptNote(title: String, source: String, kind: String, duration: Double,
                    segments: [Segment], extra: [String: String] = [:]) throws -> Note {
    let date = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone(identifier: "America/Los_Angeles")!, formatOptions: [.withFullDate])
    let slug = slugify(title).isEmpty ? UUID().uuidString.prefix(8).lowercased() : slugify(title)
    let path = Config.sourcesDir.appendingPathComponent("\(date.replacingOccurrences(of: "-", with: ""))-\(slug).md")
    var meta = extra
    meta["title"] = title
    meta["source"] = source
    meta["kind"] = kind
    meta["ingested"] = date
    meta["duration"] = formatTime(duration)
    var body = "\n# \(title)\n\nSource: \(source)\n\n## Transcript\n\n"
    for s in segments { body += "[\(formatTime(s.start))] \(s.text)\n" }
    let note = Note(path: path, meta: meta, body: body)
    try note.write()
    return note
}
