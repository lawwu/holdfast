import Foundation

// MARK: - Opening containers

/// The files inside folders and containers: zip archives (including Day One
/// exports), mailboxes (an .mbox file or Apple Mail's exported .mbox folder),
/// Evernote exports, and a message's attachments. Anything written lands in a
/// staging folder in the app state, never the vault; callers remove it when done.
enum Expand {
    /// Containers inside containers are opened this deep.
    static let maxDepth = 3

    /// A name safe to use as one file name: no path separators, control characters or
    /// leading dots, at most 120 characters (keeping the extension).
    static func safeName(_ name: String, fallback: String = "attachment") -> String {
        var n = name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined()
        n = n.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespaces)
        while n.hasPrefix(".") { n.removeFirst() }
        if n.isEmpty { n = fallback }
        if n.count > 120 {
            let ext = (n as NSString).pathExtension
            n = String(n.prefix(120 - ext.count - 1)) + (ext.isEmpty ? "" : "." + ext)
        }
        return n
    }

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
                // Apple Mail's "Export Mailbox": Inbox.mbox/mbox (the messages) plus bookkeeping files.
                if f.lastPathComponent == "mbox", f.deletingLastPathComponent().pathExtension.lowercased() == "mbox" {
                    let r = mailbox(f, staging: staging, depth: depth)
                    files += r.files; skipped += r.skipped
                    continue
                }
                if ["info.plist", "table_of_contents"].contains(f.lastPathComponent.lowercased()),
                   f.deletingLastPathComponent().pathExtension.lowercased() == "mbox" { continue }
                let r = Self.files(f, staging: staging, depth: depth)
                files += r.files; skipped += r.skipped
            }
            return (files, skipped)
        }
        let ext = url.pathExtension.lowercased()
        let name = safeName(url.deletingPathExtension().lastPathComponent, fallback: "file")
        let out = Drop.unique(staging.appendingPathComponent(name), ifExists: true)
        guard depth < maxDepth || !Formats.containers.contains(ext) else { return ([], [url]) }
        do {
            switch ext {
            case "zip":
                if let entries = try? DayOne.entries(url), !entries.isEmpty {
                    return (write(entries, to: out), [])
                }
                let z = try Formats.ZipDir(url)   // size-checked, UTF-8 names, no "../"
                try fm.createDirectory(at: out, withIntermediateDirectories: true)
                for e in z.entries {
                    let dest = out.appendingPathComponent(e)
                    try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? fm.copyItem(at: z.root.appendingPathComponent(e), to: dest)
                }
                return files(out, staging: staging, depth: depth + 1)
            case "mbox":
                return mailbox(url, staging: staging, depth: depth)
            case "enex":
                let (notes, lost) = Evernote.notes(try Data(contentsOf: url))
                return (write(notes, to: out), lost > 0 ? [url] : [])
            case "eml":
                // The message itself, then each attachment as its own file (one bad attachment skips only itself).
                let mail = Mail.parse(try Data(contentsOf: url))
                var files = [url], skipped: [URL] = []
                if !mail.attachments.isEmpty {
                    let dir = Drop.unique(staging.appendingPathComponent(name + " attachments"), ifExists: true)
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                    for a in mail.attachments {
                        let f = Drop.unique(dir.appendingPathComponent(safeName(a.name)), ifExists: true)
                        guard (try? a.data.write(to: f)) != nil else { skipped.append(URL(fileURLWithPath: a.name)); continue }
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

    /// An mbox, split message by message into .eml files without reading it all into memory.
    static func mailbox(_ url: URL, staging: URL, depth: Int) -> (files: [URL], skipped: [URL]) {
        let out = Drop.unique(staging.appendingPathComponent(safeName(url.deletingPathExtension().lastPathComponent, fallback: "mailbox")), ifExists: true)
        guard (try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)) != nil,
              let msgs = try? Mailbox.split(url, into: out) else { return ([], [url]) }
        var files: [URL] = [], skipped: [URL] = []
        for f in msgs {
            let r = Self.files(f, staging: staging, depth: depth + 1)
            files += r.files; skipped += r.skipped
        }
        return (files, skipped)
    }

    /// Writes generated Markdown notes (Day One entries, Evernote notes) into a folder; a bad one is skipped alone.
    static func write(_ notes: [(name: String, text: String)], to dir: URL) -> [URL] {
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return [] }
        return notes.compactMap { n in
            let f = Drop.unique(dir.appendingPathComponent(safeName(String(n.name.prefix(90)), fallback: "note") + ".md"), ifExists: true)
            return (try? n.text.write(to: f, atomically: true, encoding: .utf8)) != nil ? f : nil
        }
    }
}

enum Mailbox {
    /// Splits an mbox into .eml files, streaming: each message starts at a "From " line after a blank line.
    static func split(_ url: URL, into dir: URL) throws -> [URL] {
        guard let fh = try? FileHandle(forReadingFrom: url) else { throw HoldfastError("can't open \(url.lastPathComponent)") }
        defer { try? fh.close() }
        var out: [URL] = []
        var current: FileHandle?
        var pending = Data()
        var prevBlank = true
        func startMessage() throws {
            try current?.close()
            let f = dir.appendingPathComponent(String(format: "%05d.eml", out.count + 1))
            FileManager.default.createFile(atPath: f.path, contents: nil)
            current = try FileHandle(forWritingTo: f)
            out.append(f)
        }
        func handle(_ raw: Data) throws {
            var line = raw
            if line.last == 0x0D { line.removeLast() }
            let isFrom = line.starts(with: Array("From ".utf8))
            if isFrom, prevBlank { try startMessage() }
            else if let c = current {
                c.write(line.starts(with: Array(">From ".utf8)) ? line.dropFirst() : line)
                c.write(Data([0x0A]))
            }
            prevBlank = line.isEmpty
        }
        while true {
            let chunk = fh.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            pending.append(chunk)
            while let nl = pending.firstIndex(of: 0x0A) {
                try handle(pending[pending.startIndex..<nl])
                pending.removeSubrange(pending.startIndex...nl)
            }
        }
        if !pending.isEmpty { try handle(pending) }
        try current?.close()
        return out
    }
}

/// Day One's JSON export (a zip with Journal.json): one Markdown note per entry.
enum DayOne {
    static func entries(_ zip: URL) throws -> [(name: String, text: String)] {
        let z = try Formats.ZipDir(zip)
        let jsons = z.entries.filter { $0.lowercased().hasSuffix(".json") && !$0.contains("/") }
        var out: [(String, String)] = []
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "America/Los_Angeles")
        day.dateFormat = "yyyy-MM-dd"
        let iso = ISO8601DateFormatter()
        for j in jsons {
            guard let obj = try? JSONSerialization.jsonObject(with: try z.read(j)) as? [String: Any],
                  let entries = obj["entries"] as? [[String: Any]], entries.first?["creationDate"] != nil else { continue }
            let journal = (j as NSString).deletingPathExtension
            for e in entries {
                let created = e["creationDate"] as? String ?? ""
                // Dates in local time (an evening entry keeps its own day), not the UTC date.
                let date = iso.date(from: created).map { day.string(from: $0) } ?? String(created.prefix(10))
                // Day One escapes Markdown punctuation with backslashes; undo only those.
                let text = (e["text"] as? String ?? "").replacingOccurrences(of: #"\\([\\`*_{}\[\]()#+\-.!>~|])"#, with: "$1", options: .regularExpression)
                let tags = (e["tags"] as? [String] ?? [])
                let first = text.split(separator: "\n").first.map { $0.replacingOccurrences(of: "#", with: "").trimmingCharacters(in: .whitespaces) } ?? "Entry"
                var meta = ["date": date, "type": "journal", "source": "Day One · \(journal)"]
                if !tags.isEmpty { meta["tags"] = tags.joined(separator: ", ") }
                // The first line becomes the title (and isn't repeated below it).
                let body = text.hasPrefix("#") ? text : "# \(first.prefix(80))\n\n" + text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n").trimmingCharacters(in: .newlines)
                out.append(("\(date) \(first.prefix(50))", Note.frontmatter(meta) + body + "\n"))
            }
        }
        return out
    }
}

/// Evernote's .enex export: one Markdown note per note.
enum Evernote {
    final class Parser: NSObject, XMLParserDelegate {
        var notes: [[String: String]] = []
        var resources = 0
        private var cur: [String: String]?
        private var buf = ""
        func parser(_ p: XMLParser, didStartElement n: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            if n == "note" { cur = [:] }
            if n == "resource" { resources += 1 }
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

    /// The notes, and how many were lost (XML the parser couldn't read past, even after
    /// removing control characters XML forbids). Attachments (resources) aren't imported.
    static func notes(_ data: Data) -> (notes: [(name: String, text: String)], lost: Int) {
        func parse(_ d: Data) -> Parser {
            let p = Parser()
            let x = XMLParser(data: d)
            x.delegate = p
            x.parse()
            return p
        }
        let expected = String(decoding: data, as: UTF8.self).components(separatedBy: "<note>").count - 1
        var p = parse(data)
        if p.notes.count < expected {
            // A stray control character (often \u{0B}) stops the parser: drop them and try again.
            let cleaned = String(decoding: data, as: UTF8.self).unicodeScalars
                .filter { $0.value >= 0x20 || $0 == "\n" || $0 == "\r" || $0 == "\t" }.map(String.init).joined()
            let q = parse(Data(cleaned.utf8))
            if q.notes.count > p.notes.count { p = q }
        }
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.timeZone = TimeZone(identifier: "UTC")
        iso.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "America/Los_Angeles")
        day.dateFormat = "yyyy-MM-dd"
        let notes = p.notes.map { n -> (name: String, text: String) in
            let title = (n["title"] ?? "Untitled").trimmingCharacters(in: .whitespacesAndNewlines)
            let date = (n["created"]).flatMap { iso.date(from: $0) }.map { day.string(from: $0) } ?? ""
            var meta = ["title": title, "source": "Evernote"]
            if !date.isEmpty { meta["date"] = date }
            if let t = n["tags"] { meta["tags"] = t }
            return ((date.isEmpty ? "" : date + " ") + title, Note.frontmatter(meta) + "# \(title)\n\n" + Formats.htmlToText(n["content"] ?? "") + "\n")
        }
        return (notes, max(0, expected - p.notes.count))
    }
}

// MARK: - Bulk import

enum BulkImport {
    struct Report {
        var notes = 0
        var tables = 0
        var skipped: [String] = []
        var folder = ""
        /// Imported notes that look like they hold full names (in counseling folders), emails,
        /// phone or account-like numbers: imported as they were, listed so they can be checked.
        var flagged: [String] = []
    }

    /// A fresh staging folder for one operation; remove it when done (cleanUp).
    static var staging: URL {
        Config.stateDir.appendingPathComponent("import-staging").appendingPathComponent(UUID().uuidString)
    }

    static func cleanUp(_ stage: URL) { try? FileManager.default.removeItem(at: stage) }
    /// Originals of converted files, kept out of the vault (like the drop folder's).
    static var originals: URL { Config.stateDir.appendingPathComponent("imported-originals") }

    /// Every file to import, each with the path it keeps under the destination folder.
    static func plan(_ sources: [URL], stage: URL) -> (items: [(file: URL, rel: String)], skipped: [URL]) {
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
        // The destination is a folder inside the vault (or the pack): no "..", no absolute path.
        let parts = folder.split(separator: "/", omittingEmptySubsequences: false)
        guard !folder.isEmpty, !folder.hasPrefix("/"), !parts.contains(where: { $0.isEmpty || $0 == ".." || $0 == "." || $0.hasPrefix(".") }) else {
            report.skipped = ["everything: \"\(folder)\" isn't a folder inside the vault"]
            return report
        }
        let stage = staging
        defer { cleanUp(stage) }
        let (items, skipped) = plan(sources, stage: stage)
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
                    let rows = try Formats.readText(item.file).replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
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
                        base = base.deletingLastPathComponent().appendingPathComponent(Expand.safeName(day + String(subj.prefix(80)), fallback: "message"))
                    }
                    let keep = originals.appendingPathComponent(folder).appendingPathComponent(item.rel)
                    if keepOriginals {
                        try fm.createDirectory(at: keep.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try? fm.copyItem(at: item.file, to: Drop.unique(keep, ifExists: true))
                    }
                    let note = Note(path: Drop.unique(base.appendingPathExtension("md"), ifExists: true),
                                    meta: ["title": title, "source": item.file.lastPathComponent, "imported": Drop.dayString(holdfast.today())],
                                    body: "\n# \(title)\n\n" + text + "\n")
                    try note.write()
                    report.notes += 1
                    let flags = privacyFlags(text, names: Profile.isCounseling(folder + "/" + item.rel))
                    if !flags.isEmpty { report.flagged.append("\(item.rel): \(flags.joined(separator: ", "))") }
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
        let stageDir = staging
        defer { cleanUp(stageDir) }
        let (items, skipped) = plan(sources, stage: stageDir)
        let stage = stageDir.standardizedFileURL.path
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
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").contains(Substring(h))
    }

    static func remove(_ h: String) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let kept = text.split(separator: "\n").filter { $0 != Substring(h) }.joined(separator: "\n")
        try? (kept.isEmpty ? "" : kept + "\n").write(to: url, atomically: true, encoding: .utf8)
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
