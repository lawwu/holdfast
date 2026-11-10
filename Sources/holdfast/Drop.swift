import AppKit
import Foundation
import Vision

// MARK: - Drop folder
//
// A folder to drop files into. The app watches it and files each one:
// - in a managed vault (counseling), it imports the file as a source, as ⌘I does;
// - in a vault indexed in place (a notes repo), the model reads the file and the
//   folder READMEs and proposes where it belongs: a new note, or an entry
//   appended to an existing one. The proposal waits in the approval inbox;
//   nothing is written into the vault until it is approved.
// Originals are moved out of the drop folder into `drop-filed/` (state folder),
// so a raw export never lands in the repo.

let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "webp", "bmp"]

enum Drop {
    /// Files dropped here get filed. In place it lives with the app state, not in the repo.
    static var dir: URL {
        Config.inPlace ? Config.stateDir.appendingPathComponent("Drop") : Config.vault.appendingPathComponent("drop")
    }
    /// Originals after filing (or a failed attempt), kept out of the vault.
    static var filedDir: URL { Config.stateDir.appendingPathComponent("drop-filed") }

    /// Characters of the dropped document the model sees when filing it.
    static let maxDocChars = 12_000
    /// A transcript (a recording, a Listen session) gets more room: a meeting's decisions come late.
    static let maxTranscriptChars = 40_000
    /// Lines like "[00:12:03] …" that make a text a transcript.
    static let transcriptMinLines = 20

    /// A recording, a transcript note (a Listen session or an imported recording, by its `kind`),
    /// or any text written as many timestamped transcript lines.
    static func isTranscript(_ url: URL, _ text: String) -> Bool {
        if audioExtensions.contains(url.pathExtension.lowercased()) { return true }
        if url.pathExtension.lowercased() == "md", let k = (try? Note.read(url))?.meta["kind"], ["stream", "recording", "video"].contains(k) { return true }
        var n = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) where line.hasPrefix("[") {
            if line.range(of: #"^\[\d{2}:\d{2}:\d{2}\] "#, options: .regularExpression) != nil { n += 1; if n >= transcriptMinLines { return true } }
        }
        return false
    }

    /// What the model sees of a long text: its beginning and its end, with the cut marked, so a
    /// long meeting's last decisions aren't lost to a first-pages-only read.
    static func excerpt(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit * 2 / 3), tail = text.suffix(limit - head.count)
        return String(head) + "\n\n[… \(text.count - limit) characters left out …]\n\n" + String(tail)
    }
    /// Related notes listed for the model, found by searching the document's opening.
    static let relatedNotes = 8
    /// Of those, how many are shown in full (so the model can see what is already recorded), and how much of each.
    static let shownNotes = 3
    static let shownChars = 4_000
    /// A file is picked up once it has not changed for this long (still copying otherwise).
    static let settleSeconds: TimeInterval = 3
    /// How often the app looks in the drop folder.
    static let pollSeconds: TimeInterval = 5

    static var supported: Set<String> {
        docExtensions.union(audioExtensions).union(imageExtensions).union(Formats.readable).union(Formats.containers)
    }

    static func ensure() { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }

    /// Files ready to file: supported, not hidden, finished copying.
    static func pending(settled: Bool = true) -> [URL] {
        ensure()
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                                 options: [.skipsHiddenFiles])) ?? []
        return items.filter { u in
            let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard v?.isRegularFile == true, supported.contains(u.pathExtension.lowercased()) else { return false }
            return !settled || Date().timeIntervalSince(v?.contentModificationDate ?? .distantPast) > settleSeconds
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Copies files the user dropped on the app window into the drop folder.
    static func add(_ urls: [URL]) throws {
        ensure()
        for u in urls {
            var dest = dir.appendingPathComponent(u.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) { dest = unique(dest) }
            try FileManager.default.copyItem(at: u, to: dest)
        }
    }

    /// Moves an original out of the drop folder; returns where it went.
    @discardableResult
    static func moveToFiled(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: filedDir, withIntermediateDirectories: true)
        var dest = filedDir.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) { dest = unique(dest) }
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }

    static func unique(_ url: URL) -> URL {
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var i = 2
        while true {
            let u = url.deletingLastPathComponent().appendingPathComponent("\(base)-\(i)" + (ext.isEmpty ? "" : ".\(ext)"))
            if !FileManager.default.fileExists(atPath: u.path) { return u }
            i += 1
        }
    }

    // MARK: text

    /// Plain text of any supported file: documents and PDFs via `extractText`,
    /// images by on-device OCR, recordings by transcription.
    static func text(of url: URL) async throws -> String {
        let ext = url.pathExtension.lowercased()
        if audioExtensions.contains(ext) {
            let t = try await transcribeAudio(url)
            return t.segments.map { "[\(formatTime($0.start))] \($0.text)" }.joined(separator: "\n")
        }
        return try extractText(url)
    }

    // MARK: filing

    /// What the model proposes for one dropped file.
    struct Filing: Decodable {
        var action: String      // "new", "append" or "skip"
        var path: String        // vault-relative .md path
        var title: String
        var markdown: String
        var why: String
        /// Who sent it or where it came from (a business, clinic, school): what filing rules key on.
        var from: String
        /// Properties for a new note's frontmatter (type, date, amount, provider…).
        var properties: [String: String]
        /// Things to do or watch for, written into the note as Tasks lines.
        var followUps: [(date: String, what: String)]

        /// Small models drop or null fields; only the action is required
        /// (a path and Markdown too, unless skipping: checked in `decide`).
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            action = try c.decode(String.self, forKey: .action)
            path = (try? c.decodeIfPresent(String.self, forKey: .path)) ?? ""
            title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
            markdown = (try? c.decodeIfPresent(String.self, forKey: .markdown)) ?? ""
            why = (try? c.decodeIfPresent(String.self, forKey: .why)) ?? ""
            from = (try? c.decodeIfPresent(LooseString.self, forKey: .from))?.value ?? ""
            let props = (try? c.decodeIfPresent([String: LooseString].self, forKey: .properties)) ?? [:]
            var clean: [String: String] = [:]
            for (k, v) in props {
                let key = Properties.key(k), val = v.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty, !val.isEmpty, !Properties.hidden.contains(key) { clean[key] = val.replacingOccurrences(of: "\n", with: " ") }
            }
            properties = clean
            let fus = (try? c.decodeIfPresent([[String: LooseString]].self, forKey: .follow_ups)) ?? []
            followUps = fus.compactMap { f in
                let what = (f["what"]?.value ?? f["task"]?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                var date = (f["date"]?.value ?? f["due"]?.value ?? "").trimmingCharacters(in: .whitespaces)
                if date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) == nil { date = "" }
                return what.isEmpty ? nil : (date, what)
            }
        }
        enum CodingKeys: String, CodingKey { case action, path, title, markdown, why, from, properties, follow_ups }

        /// The text a filing saves, for scoring: title, entry, properties, follow-ups.
        var savedText: String {
            ([title, markdown] + properties.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
                + followUps.map { "\($0.what) \($0.date)" }).joined(separator: "\n")
        }
    }

    static let instructions = """
    You file a document that was dropped into this knowledge base. Decide where it belongs and write what should be saved.

    - Follow the folder READMEs below: they say where each kind of thing is recorded (a log, a dated table, one note per item).
    - If a README says events of this kind go in an existing log or note, append to that note ("append"). Otherwise create a new note ("new") in the right folder, named like its neighbours (lowercase, hyphens, dated YYYY-MM-DD or YYYYMM_ prefixes when the folder uses them).
    - Write a short summary and the facts worth finding later: dates, amounts, providers or businesses, decisions, follow-ups. Do not paste the whole document.
    - For "append", write only the lines to add: a table row matching that table's columns, or a dated section. For a CSV file, one CSV line per row, matching its header.
    - For "new", write the whole note, starting with a "# " title.
    - Never include account numbers, card numbers, policy or member ids, passwords or other credentials.
    - Anything about counseling or the care of a person (ministry folders): initials only, never full names.
    - Dates as YYYY-MM-DD, America/Los_Angeles.
    - If the notes shown below already record this document (same date and event), reply with "action": "skip" and say where in "why".
    - "from": who sent it or where it came from: the business, clinic, school or person, as named on the document (initials only for a counselee).
    - "properties" (for "new" only; {} for "append"): a few short fields to sort and find the note by: "type" (one lowercase word: visit, invoice, receipt, statement, policy, letter, event, recipe, report…), "date" (YYYY-MM-DD), and when the document has them "amount" (a number, no currency sign), "provider" (the business or clinic), "person" (who it's about; initials in counseling).
    - "follow_ups": things to do or watch for that the document asks for or implies (a renewal, a next visit, a bill due, a form to return), each {"date": "YYYY-MM-DD" or "", "what": "short imperative"}. [] if none.

    Reply with one JSON object and nothing else:
    {"action": "new" | "append" | "skip", "path": "folder/sub/file.md", "title": "…", "markdown": "…", "why": "one sentence: why this place", "from": "…", "properties": {"type": "…", "date": "…"}, "follow_ups": [{"date": "…", "what": "…"}]}
    """

    /// What the model decided for one file, before anything is written.
    struct Decision {
        var filing: Filing          // action "skip" when already recorded
        var flags: [String]
        var stats: GenStats
        var reply: String
        /// The filing rule that fixed the destination, if one matched.
        var rule: FilingRule? = nil
    }

    /// Asks the model where a dropped file belongs. Writes nothing.
    static func decide(_ url: URL, text: String, embedder: Embedder?, llm askedLLM: LLMBackend) async throws -> Decision {
        let limit = isTranscript(url, text) ? maxTranscriptChars : maxDocChars
        let doc = excerpt(text, limit: limit)
        let probe = url.deletingPathExtension().lastPathComponent + "\n" + String(doc.prefix(1500))
        let hits = (try? await search(probe, embedder: embedder, limit: 24, packs: false)) ?? []  // filing goes into your notes, never a pack
        // A document that looks like counseling material is filed with this Mac's model, never another Mac's.
        var llm = askedLLM
        if llm is RemoteBackend, Remote.touchesCounseling(Array(hits.prefix(relatedNotes))) {
            llm = try await MLXBackend.shared()
            Remote.keptLocal = true
        }
        var seen = Set<String>(), related: [String] = [], shown: [String] = []
        for h in hits where !h.relPath.hasPrefix("@") && seen.insert(h.relPath).inserted {
            related.append("- \(h.relPath) — \(h.title)")
            let isReadme = h.relPath.lowercased().hasSuffix("readme.md")
            if !isReadme, shown.count < shownNotes,
               let body = try? String(contentsOf: Config.vault.appendingPathComponent(h.relPath), encoding: .utf8) {
                shown.append("## \(h.relPath)\n\n" + String(body.prefix(shownChars)))
            }
            if related.count == relatedNotes { break }
        }
        let manuals = Manuals.forPassages(hits).map { "## \($0.path)\n\n\($0.text)" }.joined(separator: "\n\n")
        let rule = Rules.match(doc, name: url.lastPathComponent)
        let ruleLine = rule.map { r in
            r.action == "new"
                ? "Filing rule: documents that mention \"\(r.match)\" go in a new note in \(r.target)/. Use that folder and \"new\".\n\n"
                : "Filing rule: documents that mention \"\(r.match)\" are appended to \(r.target). Use that path and \"append\".\n\n"
        } ?? ""
        let user = ruleLine + """
        \(Agent.vaultOverview())
        Notes that look related:
        \(related.isEmpty ? "(none found)" : related.joined(separator: "\n"))

        The closest of those, as they are now:

        \(shown.isEmpty ? "(none)" : shown.joined(separator: "\n\n"))

        Folder READMEs:

        \(manuals.isEmpty ? "(none)" : manuals)

        ---
        Dropped file: \(url.lastPathComponent)\(text.count > limit ? " (its beginning and end; \(text.count) characters in all)" : "")

        \(doc)
        """
        let system = [instructions, todayLine()].joined(separator: "\n\n")
        let out = OutputBuffer()
        let stats = try await llm.chat(system: system, user: user, temperature: Config.filingTemperature) { out.append($0) }
        var f = try parse(stripThoughts(out.text))
        if f.action.lowercased() == "skip" {
            f.action = "skip"
            return Decision(filing: f, flags: [], stats: stats, reply: out.text, rule: rule)
        }
        if let r = rule {  // the rule decides the place; the model only writes the entry
            f.action = r.action
            f.path = r.action == "new" ? r.target + "/" + (f.path as NSString).lastPathComponent : r.target
        }
        if f.action.lowercased() != "new" { f.properties = [:] }
        if f.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw HoldfastError("the model proposed \(f.action) \(f.path) but wrote nothing to save")
        }
        f = try validate(f)
        if f.path.lowercased().hasSuffix(".csv"),
           let csvText = try? String(contentsOf: Config.vault.appendingPathComponent(f.path), encoding: .utf8),
           csvRows(f.markdown, for: csvText).isEmpty {
            throw HoldfastError("the model proposed a row for \(f.path) but didn't write one matching its columns")
        }
        if f.title.trimmingCharacters(in: .whitespaces).isEmpty {
            f.title = (f.action == "append" ? "Add to " : "") + (f.path as NSString).lastPathComponent
        }
        // Names matter in counseling folders (initials only); elsewhere a shop or clinic name is the point.
        let counseling = Profile.forPath(f.path).id == Profile.counseling.id
        let flags = privacyFlags(f.savedText, names: counseling)
        return Decision(filing: f, flags: flags, stats: stats, reply: out.text, rule: rule)
    }

    /// Asks the model where a dropped file belongs; the proposal goes to the inbox.
    static func propose(_ url: URL, text: String, embedder: Embedder?, llm: LLMBackend, model: String) async throws -> (Note, [String], FilingRule?) {
        let d = try await decide(url, text: text, embedder: embedder, llm: llm)
        let f = d.filing, flags = d.flags
        // A transcript's filing is a summary or a log line; the whole transcript is offered too,
        // as its own note beside it, so every word stays searchable. Even when the summary is skipped.
        let keptTranscript = isTranscript(url, text) ? (try? transcriptProposal(url, text: text, near: f.path, model: model)) : nil
        if f.action == "skip" {
            throw AlreadyFiled(why: f.why + (keptTranscript == nil ? "" : " The full transcript is in the Inbox if you want to keep it."))
        }
        let today = dayString(holdfast.today())
        var meta = ["title": f.title, "kind": "filing", "proposed_by": "Drop folder · \(model)", "proposed": today,
                    "target": f.path, "action": f.action, "why": f.why, "original": url.lastPathComponent]
        if !flags.isEmpty { meta["privacy_flags"] = flags.joined(separator: "; ") }
        if !f.from.isEmpty { meta["from"] = f.from }
        for (k, v) in f.properties { meta["prop_" + k] = v }
        if !f.followUps.isEmpty { meta["follow_ups"] = f.followUps.map { ($0.date.isEmpty ? "" : $0.date + " ") + $0.what }.joined(separator: "; ") }
        if let r = d.rule { meta["rule"] = r.match + (r.auto ? " (auto)" : "") }
        let slug = slugify(f.title).isEmpty ? "filing" : slugify(f.title)
        let path = Config.inboxDir.appendingPathComponent("\(today.replacingOccurrences(of: "-", with: ""))-\(slug).md")
        let note = Note(path: Drop.unique(path, ifExists: true), meta: meta, body: "\n" + f.markdown.trimmingCharacters(in: .whitespacesAndNewlines) + "\n")
        try note.write()
        return (note, flags, d.rule)
    }

    /// The whole transcript as a proposal of its own: a new note next to where the summary goes
    /// (or in transcripts/ when there is no such place), named for the recording and dated.
    static func transcriptProposal(_ url: URL, text: String, near target: String, model: String) throws -> Note {
        let recorded = try? Note.read(url)
        let name = recorded?.meta["title"] ?? url.deletingPathExtension().lastPathComponent
        let today = dayString(holdfast.today())
        var folder = (target as NSString).deletingLastPathComponent
        if folder.isEmpty || (try? safeTarget(folder + "/x.md")) == nil { folder = "transcripts" }
        let slug = slugify(name).isEmpty ? "recording" : String(slugify(name).prefix(60))
        var path = folder + "/" + (slug.hasPrefix(today) ? slug : today + "-" + slug) + "-transcript.md"
        // Built from the folder and the free file name: `relative` can't be trusted on a file that
        // doesn't exist yet (macOS drops /private from /private/tmp paths only for files that do).
        path = folder + "/" + unique(try safeTarget(path), ifExists: true).lastPathComponent
        let body: String
        if let r = recorded, r.body.contains("## Transcript") {
            body = r.body
        } else {
            body = "\n# \(name)\n\n## Transcript\n\n" + text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        }
        var meta = ["title": "Full transcript — \(name)", "kind": "filing", "proposed_by": "Drop folder · \(model)", "proposed": today,
                    "target": path, "action": "new", "original": url.lastPathComponent,
                    "why": "The whole transcript, kept beside its summary so every word can be found later.",
                    "prop_type": "transcript", "prop_date": today]
        if let dur = recorded?.meta["duration"] { meta["prop_duration"] = dur }
        let flags = privacyFlags(body, names: Profile.isCounseling(path))
        if !flags.isEmpty { meta["privacy_flags"] = flags.joined(separator: "; ") }
        let note = Note(path: unique(Config.inboxDir.appendingPathComponent("\(today.replacingOccurrences(of: "-", with: ""))-\(slug)-transcript.md"), ifExists: true),
                        meta: meta, body: body)
        try note.write()
        return note
    }

    /// A proposal's follow-ups, back from its "YYYY-MM-DD what; …" form.
    static func followUps(_ item: Note) -> [(date: String, what: String)] {
        (item.meta["follow_ups"] ?? "").components(separatedBy: "; ").compactMap { s in
            let t = s.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { return nil }
            if t.range(of: #"^\d{4}-\d{2}-\d{2} "#, options: .regularExpression) != nil {
                return (String(t.prefix(10)), String(t.dropFirst(11)))
            }
            return ("", t)
        }
    }

    /// A proposal's properties (stored as prop_* in the inbox note).
    static func properties(_ item: Note) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in item.meta where k.hasPrefix("prop_") { out[String(k.dropFirst(5))] = v }
        return out
    }

    /// The JSON object in the model's reply (it may wrap it in a code fence).
    static func parse(_ reply: String) throws -> Filing {
        guard let a = reply.firstIndex(of: "{"), let b = firstObjectEnd(reply, from: a) ?? reply.lastIndex(of: "}"), a < b,
              let data = String(reply[a...b]).data(using: .utf8) else {
            throw HoldfastError("the model's filing reply had no JSON: \(reply.prefix(200))")
        }
        do { return try JSONDecoder().decode(Filing.self, from: data) }
        catch { throw HoldfastError("couldn't read the model's filing reply: \(error)") }
    }

    /// The entry's lines that are rows of this CSV: CSV lines or Markdown table rows
    /// with exactly the header's number of columns. Anything else (bullets, prose) is dropped.
    static func csvRows(_ entry: String, for csvText: String) -> [String] {
        let header = (CSV.parse(String(csvText.prefix { $0 != "\n" })).first ?? []).map { $0.lowercased() }
        let width = header.count
        return entry.components(separatedBy: "\n").compactMap { l -> String? in
            let t = l.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, t.range(of: #"^\|?[\s:|-]+\|?$"#, options: .regularExpression) == nil else { return nil }
            let cells = t.hasPrefix("|")
                ? t.trimmingCharacters(in: CharacterSet(charactersIn: "|")).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                : (CSV.parse(t).first ?? [])
            guard cells.count == width, cells.map({ $0.lowercased() }) != header else { return nil }  // not the header again
            return Formats.csvLine(cells)
        }
    }

    /// Where the first JSON object closes (models sometimes add a second block or a note after it).
    static func firstObjectEnd(_ s: String, from start: String.Index) -> String.Index? {
        var depth = 0, inString = false, escaped = false
        var i = start
        while i < s.endIndex {
            let c = s[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" { inString = true }
            else if c == "{" { depth += 1 }
            else if c == "}" { depth -= 1; if depth == 0 { return i } }
            i = s.index(after: i)
        }
        return nil
    }

    /// Keeps the target inside the vault, a Markdown file, and consistent with the action.
    static func validate(_ f: Filing) throws -> Filing {
        var f = f
        var p = f.path.trimmingCharacters(in: .whitespaces)
        while p.hasPrefix("./") || p.hasPrefix("/") { p.removeFirst(p.hasPrefix("./") ? 2 : 1) }
        let parts = p.split(separator: "/")
        if p.isEmpty || parts.contains("..") || parts.contains(where: { $0.hasPrefix(".") }) {
            throw HoldfastError("the model proposed a path outside the vault: \(f.path)")
        }
        // A folder ("life/recipes/" or a folder rule with no name): name the note after its title.
        if p.hasSuffix("/") || (p as NSString).lastPathComponent.lowercased() == ".md" {
            let slug = slugify(f.title).isEmpty ? "note" : slugify(f.title)
            p = (p.hasSuffix("/") ? p : (p as NSString).deletingLastPathComponent + "/") + slug + ".md"
            while p.hasPrefix("/") { p.removeFirst() }
        }
        _ = try safeTarget(p)
        // A row for an existing CSV table goes into that table; anything else is a Markdown note.
        let csv = p.lowercased().hasSuffix(".csv") && FileManager.default.fileExists(atPath: Config.vault.appendingPathComponent(p).path)
        if !csv && !p.hasSuffix(".md") { p += ".md" }
        f.path = p
        if csv { f.properties = [:] }
        let exists = FileManager.default.fileExists(atPath: Config.vault.appendingPathComponent(p).path)
        // An existing note is added to, never overwritten or duplicated as "note-2".
        f.action = exists ? "append" : "new"
        return f
    }

    static func relative(_ u: URL) -> String {
        let root = Config.vault.resolvingSymlinksInPath().path + "/"
        let p = u.resolvingSymlinksInPath().path
        return p.hasPrefix(root) ? String(p.dropFirst(root.count)) : p
    }

    static func unique(_ url: URL, ifExists: Bool) -> URL {
        FileManager.default.fileExists(atPath: url.path) ? unique(url) : url
    }

    /// Writes an approved filing into the vault. Appends go after the last
    /// line of the note's last table when the addition is a table row,
    /// otherwise at the end of the note.
    /// One filing (or undo) at a time across every process: the app, the CLI and the MCP server
    /// all write the same notes and filing log. An advisory file lock in the vault's state folder.
    static func withWriteLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: Config.stateDir, withIntermediateDirectories: true)
        let path = Config.stateDir.appendingPathComponent(".write.lock").path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw HoldfastError("can't open the vault's write lock") }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return try body()
    }

    /// A vault-relative path as a file URL inside the vault, or an error: no absolute paths,
    /// "..", hidden components, the app's state folder or a knowledge pack.
    static func safeTarget(_ target: String) throws -> URL {
        let parts = target.split(separator: "/", omittingEmptySubsequences: false)
        guard !target.isEmpty, !target.hasPrefix("/"), !Packs.isPack(target), !target.hasPrefix("@"),
              !parts.contains(where: { $0.isEmpty || $0 == ".." || $0 == "." || $0.hasPrefix(".") }) else {
            throw HoldfastError("refusing to write outside the vault: \(target)")
        }
        let root = Config.vault.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let url = Config.vault.appendingPathComponent(target)
        let resolved = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard resolved.hasPrefix(root) || resolved == root else { throw HoldfastError("refusing to write outside the vault: \(target)") }
        return url
    }

    /// Writes an approved filing into the vault. Appends go after the last
    /// line of the note's last table when the addition is a table row,
    /// otherwise at the end of the note.
    static func apply(_ item: Note) throws -> URL {
        try withWriteLock { try applyLocked(item) }
    }

    /// For callers already holding the write lock.
    static func applyClaimed(_ item: Note) throws -> URL { try applyLocked(item) }

    private static func applyLocked(_ item: Note) throws -> URL {
        guard let target = item.meta["target"] else { throw HoldfastError("filing has no target") }
        var dest = try safeTarget(target)
        if item.meta["action"] == "edit" { return try Edits.apply(item, at: dest, target: target) }  // a change asked for in Ask
        let entry = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let existed = FileManager.default.fileExists(atPath: dest.path)
        let before = Versions.snapshot(dest, reason: "filing")
        let action = item.meta["action"] ?? "new"
        let fus = followUps(item)
        var written: String
        var extra: [String] = []
        if existed, action == "link", let text = try? String(contentsOf: dest, encoding: .utf8) {
            // A cross-link: one line under the note's "## See also".
            try appendUnder("## See also", lines: [entry], to: text).write(to: dest, atomically: true, encoding: .utf8)
            written = entry
        } else if existed, action == "append", target.lowercased().hasSuffix(".csv"), let data = try? Data(contentsOf: dest) {
            let bom = data.starts(with: [0xEF, 0xBB, 0xBF])
            var text = String(decoding: bom ? data.dropFirst(3) : data, as: UTF8.self)
            let rows = csvRows(entry, for: text)
            guard !rows.isEmpty else { throw HoldfastError("the proposal has no row matching \(target)'s columns; edit it into a CSV line first") }
            // Keep the file's line endings (Excel writes \r\n, which Swift sees as one character) and its BOM.
            let eol = text.contains("\r\n") ? "\r\n" : "\n"
            if !(text.hasSuffix("\n") || text.hasSuffix("\r\n")) { text += eol }
            written = rows.joined(separator: eol)
            text += written + eol
            try ((bom ? Data([0xEF, 0xBB, 0xBF]) : Data()) + Data(text.utf8)).write(to: dest, options: .atomic)
        } else if existed, action == "append", var text = try? String(contentsOf: dest, encoding: .utf8) {
            let lines = entry.components(separatedBy: "\n")
            var all = text.components(separatedBy: "\n")
            if entry.hasPrefix("|"), let last = all.lastIndex(where: { $0.hasPrefix("|") }) {
                // Table rows go after the table's last row; a header or separator the model
                // repeated is dropped, and anything that isn't a row goes at the end of the note.
                // The header of the table being appended to: the first row of its run of rows.
                var top = last
                while top > 0, all[top - 1].hasPrefix("|") { top -= 1 }
                let headerLine = all[top].trimmingCharacters(in: .whitespaces)
                let rows = lines.filter { l in
                    let t = l.trimmingCharacters(in: .whitespaces)
                    return t.hasPrefix("|") && t.range(of: #"^\|?[\s:|-]+\|?$"#, options: .regularExpression) == nil && t != headerLine
                }
                let rest = lines.filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("|") }
                    .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                all.insert(contentsOf: rows, at: last + 1)
                text = all.joined(separator: "\n")
                written = rows.joined(separator: "\n")
                if !rest.isEmpty {
                    text = text.trimmingCharacters(in: .newlines) + "\n\n" + rest + "\n"
                    extra.append(contentsOf: rest.components(separatedBy: "\n"))
                }
            } else {
                text = text.trimmingCharacters(in: .newlines) + "\n\n" + entry + "\n"
                written = entry
            }
            text = Upcoming.append(fus, to: text)
            extra += fus.map(Upcoming.line)
            try text.write(to: dest, atomically: true, encoding: .utf8)
        } else {
            if existed { dest = unique(dest) }
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            let body = Upcoming.append(fus, to: entry + "\n")
            let props = properties(item)
            if props.isEmpty {
                try body.write(to: dest, atomically: true, encoding: .utf8)
            } else {
                try Note(path: dest, meta: props, body: body).write()
            }
            written = (try? String(contentsOf: dest, encoding: .utf8)) ?? body
        }
        // The document it came from, kept in the vault beside the note and linked under "## Originals".
        var kept: String?
        if action != "link", let k = try? Originals.keep(original: item.meta["original"], for: relative(dest)),
           let text = try? String(contentsOf: dest, encoding: .utf8) {
            let line = Originals.link(k, from: relative(dest))
            try appendUnder("## Originals", lines: [line], to: text).write(to: dest, atomically: true, encoding: .utf8)
            extra.append(line)
            kept = k
            if !existed { written = (try? String(contentsOf: dest, encoding: .utf8)) ?? written }
        }
        let after = (try? String(contentsOf: dest, encoding: .utf8)) ?? ""
        var proposal = item.meta
        proposal["target"] = relative(dest)
        var record = FilingRecord(title: item.meta["title"] ?? relative(dest), target: relative(dest),
                                  action: existed ? action : "new", original: item.meta["original"],
                                  snapshot: existed ? before?.path : nil, after: FilingLog.hash(after), addition: written,
                                  proposal: proposal, proposalBody: item.body, rule: item.meta["rule"])
        record.extraLines = extra.isEmpty ? nil : extra
        record.originalHash = item.meta["original_hash"]
        record.keptOriginal = kept
        FilingLog.add(record)
        return dest
    }

    static func dayString(_ d: Date) -> String {
        ISO8601DateFormatter.string(from: d, timeZone: TimeZone(identifier: "America/Los_Angeles")!, formatOptions: [.withFullDate])
    }

    /// Files one dropped file. Managed vaults import it; in-place vaults get a
    /// proposal in the inbox. The original leaves the drop folder either way.
    static func process(_ dropped: URL, embedder: Embedder?, llm: LLMBackend?, model: String) async throws -> String {
        // Out of the drop folder first: a file that crashes a reader isn't retried on every launch.
        let url = (try? moveToFiled(dropped)) ?? dropped
        let ext = url.pathExtension.lowercased()
        // Containers (zip, mailbox, Evernote export) open into the drop folder; each file is filed on its own.
        if Formats.containers.contains(ext) {
            let stage = BulkImport.staging
            defer { BulkImport.cleanUp(stage) }
            let r = Expand.files(url, staging: stage)
            for f in r.files { try FileManager.default.moveItem(at: f, to: unique(dir.appendingPathComponent(f.lastPathComponent), ifExists: true)) }
            return "Opened \(url.lastPathComponent): \(r.files.count) files to file" + (r.skipped.isEmpty ? "" : ", \(r.skipped.count) skipped")
        }
        // The same file filed before (byte for byte) is not filed again. The hash is remembered
        // when a filing is approved (or imported), and forgotten again on undo.
        let hash = FiledHashes.hash(url)
        if let h = hash, FiledHashes.contains(h) { throw AlreadyFiled(why: "the same file was filed before") }
        func done(_ msg: String) -> String { if let h = hash { FiledHashes.add(h) }; return msg }
        // A message's attachments go into the drop folder to be filed on their own.
        if ext == "eml", let mail = try? Mail.parse(Data(contentsOf: url)) {
            for a in mail.attachments where Drop.supported.contains((a.name as NSString).pathExtension.lowercased()) {
                try? a.data.write(to: unique(dir.appendingPathComponent(Expand.safeName(a.name)), ifExists: true))
            }
        }
        if !Config.inPlace {
            if audioExtensions.contains(url.pathExtension.lowercased()) {
                let n = try await ingestAudio(url, title: nil, tags: [])
                return done("Imported \(n.title)")
            }
            let n = try ingestDocument(url, root: nil, tags: [])
            return done("Imported \(n.title)")
        }
        let text = try await self.text(of: url)
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 else {
            throw HoldfastError("\(url.lastPathComponent): no readable text")
        }
        guard let llm else { throw HoldfastError("no model loaded to file \(url.lastPathComponent)") }
        var (n, flags, rule) = try await propose(url, text: text, embedder: embedder, llm: llm, model: model)
        if let h = hash { n.meta["original_hash"] = h; try n.write() }
        // An automatic rule files without asking only when nothing in the entry looks personal
        // (names included) and nothing about it is counseling; otherwise it waits for approval.
        let target = n.meta["target"] ?? ""
        let personal = privacyFlags((n.meta["title"] ?? "") + "\n" + n.body, names: true)
        if rule?.auto == true, flags.isEmpty, personal.isEmpty, !Profile.isCounseling(target), !Profile.isCounseling(Drop.relative(url)) {
            let saved = try approve(n.id)
            return "Filed to \(Drop.relative(saved.path)) by rule"
        }
        return "Proposed \(target)"
    }
}

/// A JSON value read as text: models write amounts and dates as numbers or strings.
struct LooseString: Decodable {
    var value: String
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let n = try? c.decode(Double.self) { value = n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n) }
        else if let b = try? c.decode(Bool.self) { value = b ? "true" : "false" }
        else { value = "" }
    }
}

/// The model found the dropped file already recorded in the vault.
struct AlreadyFiled: Error, CustomStringConvertible {
    var why: String
    var description: String { "already in the vault — \(why)" }
}

/// Collects streamed tokens from a @Sendable callback.
final class OutputBuffer: @unchecked Sendable {
    private var parts: [String] = []
    private let lock = NSLock()
    func append(_ s: String) { lock.lock(); parts.append(s); lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return parts.joined() }
}

/// On-device OCR of an image (receipts, screenshots, photos of paper).
func ocrImage(_ url: URL) throws -> String {
    guard let img = NSImage(contentsOf: url), let src = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        throw HoldfastError("can't open image \(url.lastPathComponent)")
    }
    // Flatten onto white: Vision reads dark text on a transparent background as nothing.
    let w = src.width, h = src.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw HoldfastError("can't read image \(url.lastPathComponent)")
    }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let cg = ctx.makeImage() else { throw HoldfastError("can't read image \(url.lastPathComponent)") }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = true
    try VNImageRequestHandler(cgImage: cg).perform([req])
    return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}
