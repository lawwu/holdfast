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

    var id: String { path.deletingPathExtension().lastPathComponent }
    var title: String { meta["title"] ?? id }
    var relPath: String {
        path.path.replacingOccurrences(of: Config.vault.path + "/", with: "")
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

func allNotes(in dirs: [URL] = [Config.sourcesDir, Config.memoryDir]) -> [Note] {
    var out: [Note] = []
    for d in dirs {
        guard let e = FileManager.default.enumerator(at: d, includingPropertiesForKeys: nil) else { continue }
        for case let u as URL in e where u.pathExtension == "md" {
            if let n = try? Note.read(u) { out.append(n) }
        }
    }
    return out.sorted { $0.path.path < $1.path.path }
}

func findNote(_ idOrPath: String) -> Note? {
    let key = idOrPath.replacingOccurrences(of: ".md", with: "")
    return allNotes(in: [Config.sourcesDir, Config.memoryDir, Config.inboxDir]).first {
        $0.id == key || $0.relPath == idOrPath || $0.relPath == key + ".md"
    }
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
