import Foundation

// MARK: - Opening containers

/// The files inside folders and containers: zip archives (including Day One
/// exports), mailboxes, Evernote exports, and a message's attachments.
/// Anything written lands in a staging folder in the app state, never the vault.
enum Expand {
    /// Containers inside containers are opened this deep.
    static let maxDepth = 3

    static func files(_ url: URL, staging: URL, depth: Int = 0) -> (files: [URL], skipped: [URL]) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return ([], [url]) }
        if isDir.boolValue {
            var files: [URL] = [], skipped: [URL] = []
            let items = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                      options: [.skipsHiddenFiles, .skipsPackageDescendants])?.compactMap { $0 as? URL } ?? []
            for f in items.sorted(by: { $0.path < $1.path }) where (try? f.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                guard !f.path.contains("/__MACOSX/") else { continue }
                let r = Self.files(f, staging: staging, depth: depth)
                files += r.files; skipped += r.skipped
            }
            return (files, skipped)
        }
        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent
        let out = Drop.unique(staging.appendingPathComponent(name), ifExists: true)
        guard depth < maxDepth || !Formats.containers.contains(ext) else { return ([], [url]) }
        do {
            switch ext {
            case "zip":
                if let entries = try? DayOne.entries(url), !entries.isEmpty {
                    return (try write(entries, to: out), [])
                }
                try fm.createDirectory(at: out, withIntermediateDirectories: true)
                _ = try run("/usr/bin/ditto", ["-x", "-k", url.path, out.path])
                return files(out, staging: staging, depth: depth + 1)
            case "mbox":
                try fm.createDirectory(at: out, withIntermediateDirectories: true)
                var files: [URL] = []
                for (i, msg) in Mailbox.split(try Data(contentsOf: url)).enumerated() {
                    let f = out.appendingPathComponent(String(format: "%05d.eml", i + 1))
                    try msg.write(to: f)
                    files += Self.files(f, staging: staging, depth: depth + 1).files
                }
                return (files, [])
            case "enex":
                return (try write(Evernote.notes(try Data(contentsOf: url)), to: out), [])
            case "eml":
                // The message itself, then each attachment as its own file.
                let mail = Mail.parse(try Data(contentsOf: url))
                var files = [url], skipped: [URL] = []
                if !mail.attachments.isEmpty {
                    let dir = Drop.unique(staging.appendingPathComponent(name + " attachments"), ifExists: true)
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    for a in mail.attachments {
                        let safe = a.name.replacingOccurrences(of: "/", with: "-")
                        let f = Drop.unique(dir.appendingPathComponent(safe), ifExists: true)
                        try a.data.write(to: f)
                        let r = Self.files(f, staging: staging, depth: depth + 1)
                        files += r.files; skipped += r.skipped
                    }
                }
                return (files, skipped)
            default:
                return Drop.supported.contains(ext) ? ([url], []) : ([], [url])
            }
        } catch {
            return ([], [url])
        }
    }

    /// Writes generated Markdown notes (Day One entries, Evernote notes) into a folder.
    static func write(_ notes: [(name: String, text: String)], to dir: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try notes.map { n in
            let safe = n.name.replacingOccurrences(of: "/", with: "-").prefix(90)
            let f = Drop.unique(dir.appendingPathComponent(safe + ".md"), ifExists: true)
            try n.text.write(to: f, atomically: true, encoding: .utf8)
            return f
        }
    }
}

enum Mailbox {
    /// Messages of an mbox file: each starts at a "From " line after a blank line.
    static func split(_ data: Data) -> [Data] {
        let lines = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var msgs: [[String]] = []
        var prevBlank = true
        for l in lines {
            if l.hasPrefix("From "), prevBlank { msgs.append([]) }
            else if !msgs.isEmpty { msgs[msgs.count - 1].append(l.hasPrefix(">From ") ? String(l.dropFirst()) : l) }
            prevBlank = l.isEmpty
        }
        return msgs.map { Data($0.joined(separator: "\n").utf8) }
    }
}

/// Day One's JSON export (a zip with Journal.json): one Markdown note per entry.
enum DayOne {
    static func entries(_ zip: URL) throws -> [(name: String, text: String)] {
        let jsons = try Formats.zipEntries(zip).filter { $0.hasSuffix(".json") && !$0.contains("/") }
        var out: [(String, String)] = []
        for j in jsons {
            guard let obj = try? JSONSerialization.jsonObject(with: try Formats.zipRead(zip, j)) as? [String: Any],
                  let entries = obj["entries"] as? [[String: Any]], entries.first?["creationDate"] != nil else { continue }
            let journal = (j as NSString).deletingPathExtension
            for e in entries {
                let date = (e["creationDate"] as? String ?? "").prefix(10)
                let text = (e["text"] as? String ?? "").replacingOccurrences(of: "\\", with: "")
                let tags = (e["tags"] as? [String] ?? [])
                let first = text.split(separator: "\n").first.map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) } ?? "Entry"
                var fm = "---\ndate: \"\(date)\"\ntype: \"journal\"\nsource: \"Day One · \(journal)\"\n"
                if !tags.isEmpty { fm += "tags: \"\(tags.joined(separator: ", "))\"\n" }
                fm += "---\n"
                // The first line becomes the title (and isn't repeated below it).
                let body = text.hasPrefix("#") ? text : "# \(first.prefix(80))\n\n" + text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n").trimmingCharacters(in: .newlines)
                out.append(("\(date) \(first.prefix(50))", fm + body + "\n"))
            }
        }
        return out
    }
}

/// Evernote's .enex export: one Markdown note per note.
enum Evernote {
    final class Parser: NSObject, XMLParserDelegate {
        var notes: [[String: String]] = []
        private var cur: [String: String]?
        private var buf = ""
        func parser(_ p: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if n == "note" { cur = [:] }
            buf = ""
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { buf += s }
        func parser(_ p: XMLParser, foundCDATA d: Data) { buf += String(decoding: d, as: UTF8.self) }
        func parser(_ p: XMLParser, didEndElement n: String, namespaceURI: String?, qualifiedName: String?) {
            switch n {
            case "title", "content", "created": if cur != nil, cur?[n] == nil { cur?[n] = buf }
            case "tag":
                if var c = cur { c["tags"] = (c["tags"].map { $0 + ", " } ?? "") + buf; cur = c }
            case "note": if let c = cur { notes.append(c) }; cur = nil
            default: break
            }
            buf = ""
        }
    }

    static func notes(_ data: Data) throws -> [(name: String, text: String)] {
        let p = Parser()
        let x = XMLParser(data: data)
        x.delegate = p
        x.parse()
        return p.notes.map { n in
            let title = (n["title"] ?? "Untitled").trimmingCharacters(in: .whitespacesAndNewlines)
            let c = n["created"] ?? ""
            let date = c.count >= 8 ? "\(c.prefix(4))-\(c.dropFirst(4).prefix(2))-\(c.dropFirst(6).prefix(2))" : ""
            var fm = "---\ntitle: \"\(title.replacingOccurrences(of: "\"", with: "'"))\"\nsource: \"Evernote\"\n"
            if !date.isEmpty { fm += "date: \"\(date)\"\n" }
            if let t = n["tags"] { fm += "tags: \"\(t)\"\n" }
            fm += "---\n"
            return ((date.isEmpty ? "" : date + " ") + title, fm + "# \(title)\n\n" + Formats.htmlToText(n["content"] ?? "") + "\n")
        }
    }
}

// MARK: - Bulk import

enum BulkImport {
    struct Report {
        var notes = 0
        var tables = 0
        var skipped: [String] = []
        var folder = ""
    }

    static var staging: URL {
        Config.stateDir.appendingPathComponent("import-staging").appendingPathComponent(Versions.stamp.string(from: Date()))
    }
    /// Originals of converted files, kept out of the vault (like the drop folder's).
    static var originals: URL { Config.stateDir.appendingPathComponent("imported-originals") }

    /// Every file to import, each with the path it keeps under the destination folder.
    static func plan(_ sources: [URL]) -> (items: [(file: URL, rel: String)], skipped: [URL]) {
        let stage = staging
        var items: [(URL, String)] = [], skipped: [URL] = []
        for src in sources {
            let r = Expand.files(src, staging: stage)
            skipped += r.skipped
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: src.path, isDirectory: &isDir)
            for f in r.files {
                let p = f.standardizedFileURL.path
                let rel: String
                if isDir.boolValue, p.hasPrefix(src.standardizedFileURL.path + "/") {
                    rel = src.lastPathComponent + "/" + String(p.dropFirst(src.standardizedFileURL.path.count + 1))
                } else if p.hasPrefix(stage.standardizedFileURL.path + "/") {
                    rel = String(p.dropFirst(stage.standardizedFileURL.path.count + 1))
                } else {
                    rel = f.lastPathComponent
                }
                items.append((f, rel))
            }
        }
        return (items, skipped)
    }

    /// "Bring in as-is": Markdown and CSV are copied; spreadsheets become CSV
    /// tables; everything else becomes a Markdown note of its text (originals kept
    /// outside the vault). No model: only OCR and transcription where needed.
    static func asIs(_ sources: [URL], into folder: String, root: URL = Config.vault, keepOriginals: Bool = true,
                     progress: @escaping @Sendable (Int, Int, String) async -> Void) async -> Report {
        var report = Report(folder: folder)
        let (items, skipped) = plan(sources)
        report.skipped = skipped.map(\.lastPathComponent)
        let dest = root.appendingPathComponent(folder)
        let fm = FileManager.default
        for (i, item) in items.enumerated() {
            await progress(i, items.count, item.rel)
            let ext = item.file.pathExtension.lowercased()
            let base = dest.appendingPathComponent((item.rel as NSString).deletingPathExtension)
            do {
                try fm.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
                switch ext {
                case "md", "markdown":
                    try fm.copyItem(at: item.file, to: Drop.unique(base.appendingPathExtension("md"), ifExists: true))
                    report.notes += 1
                case "csv":
                    try fm.copyItem(at: item.file, to: Drop.unique(base.appendingPathExtension("csv"), ifExists: true))
                    report.tables += 1
                case "tsv":
                    let rows = try String(contentsOf: item.file, encoding: .utf8).components(separatedBy: "\n")
                        .map { $0.components(separatedBy: "\t") }
                    try (rows.map(Formats.csvLine).joined(separator: "\n")).write(to: Drop.unique(base.appendingPathExtension("csv"), ifExists: true),
                                                                                   atomically: true, encoding: .utf8)
                    report.tables += 1
                case "xlsx":
                    for s in try Formats.xlsxSheets(item.file) where !s.rows.isEmpty {
                        let f = Drop.unique(URL(fileURLWithPath: base.path + "-" + slugify(s.name) + ".csv"), ifExists: true)
                        try s.rows.map(Formats.csvLine).joined(separator: "\n").write(to: f, atomically: true, encoding: .utf8)
                        report.tables += 1
                    }
                default:
                    let text = try await Drop.text(of: item.file).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { report.skipped.append(item.rel + " (no text)"); continue }
                    var title = item.file.deletingPathExtension().lastPathComponent
                    var base = base
                    if ext == "eml", let m = try? Mail.parse(Data(contentsOf: item.file)), let subj = m.header("Subject"), !subj.isEmpty {
                        // Messages are named by date and subject, not their file name.
                        title = subj
                        let day = m.header("Date").flatMap { Mail.date($0) }.map { Drop.dayString($0) + " " } ?? ""
                        base = base.deletingLastPathComponent().appendingPathComponent(day + subj.replacingOccurrences(of: "/", with: "-").prefix(80))
                    }
                    let keep = originals.appendingPathComponent(folder).appendingPathComponent(item.rel)
                    if keepOriginals {
                        try fm.createDirectory(at: keep.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? fm.copyItem(at: item.file, to: Drop.unique(keep, ifExists: true))
                    }
                    let note = Note(path: Drop.unique(base.appendingPathExtension("md"), ifExists: true),
                                    meta: ["title": title, "source": item.file.lastPathComponent, "imported": Drop.dayString(mackb.today())],
                                    body: "\n# \(title)\n\n" + text + "\n")
                    try note.write()
                    report.notes += 1
                }
            } catch {
                report.skipped.append("\(item.rel) (\(error))")
            }
        }
        await progress(items.count, items.count, "")
        return report
    }

    /// "File each one": opens containers and puts every file in the drop folder,
    /// where the model proposes a place for each. Returns how many were queued.
    static func queue(_ sources: [URL]) throws -> (queued: Int, skipped: [String]) {
        Drop.ensure()
        let (items, skipped) = plan(sources)
        let stage = staging.standardizedFileURL.path
        for item in items {
            let dest = Drop.unique(Drop.dir.appendingPathComponent(item.file.lastPathComponent), ifExists: true)
            // Staged files (opened from containers) move; the person's own files are copied.
            if item.file.standardizedFileURL.path.hasPrefix(stage) {
                try FileManager.default.moveItem(at: item.file, to: dest)
            } else {
                try FileManager.default.copyItem(at: item.file, to: dest)
            }
        }
        return (items.count, skipped.map(\.lastPathComponent))
    }
}

// MARK: - Duplicates

/// Hashes of files already filed, so the same file dropped twice isn't filed twice.
enum FiledHashes {
    static var url: URL { Config.stateDir.appendingPathComponent("filed-hashes.txt") }

    static func hash(_ file: URL) -> String? {
        (try? Data(contentsOf: file)).map { FilingLog.hashData($0) }
    }

    static func contains(_ h: String) -> Bool {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").contains(h)
    }

    static func add(_ h: String) {
        if let fh = try? FileHandle(forWritingTo: url) {
            fh.seekToEndOfFile(); fh.write(Data((h + "\n").utf8)); try? fh.close()
        } else {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? (h + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
