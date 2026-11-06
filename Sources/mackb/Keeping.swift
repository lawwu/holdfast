import CryptoKit
import Foundation

// MARK: - Keeping what's filed
//
// Four things that make filing safe to trust and easy to reuse, all in plain
// files a person can read:
// - Versions: a copy of a note before the app changes it (a filing, an edit,
//   a restore), so any note can go back to an earlier copy.
// - FilingLog: every approved filing, so it can be undone (and the proposal
//   put back in the inbox).
// - Upcoming: follow-ups written as Obsidian Tasks lines (`- [ ] … 📅 date`),
//   gathered from every note.
// - Rules: "documents that mention X go to Y", learned from approvals and kept
//   as a Markdown table the person can edit.
// All of it lives in the vault's state folder, never in the vault itself,
// except the follow-up lines and properties that filing writes into notes.

// MARK: versions

enum Versions {
    static var dir: URL { Config.stateDir.appendingPathComponent("versions") }
    /// Copies kept per note; the oldest go first.
    static let keepPerNote = 50
    /// Editor saves keep at most one copy this often; filings and restores always keep one.
    static let editInterval: TimeInterval = 10 * 60

    struct Version: Identifiable, Hashable {
        var url: URL
        var date: Date
        var reason: String
        var id: URL { url }
    }

    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    /// A note's versions live in versions/<vault path>/ (a folder per note).
    static func folder(_ relPath: String) -> URL { dir.appendingPathComponent(relPath) }

    /// Saves the note's current text before the app changes it. Returns the copy
    /// (or the latest one, if the text hasn't changed since); nil if there is no
    /// file yet, it isn't in the vault, or an edit copy was taken recently.
    @discardableResult
    static func snapshot(_ url: URL, reason: String) -> URL? {
        let rel = Drop.relative(url)
        guard !rel.hasPrefix("/"), let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let existing = list(rel)
        if let last = existing.first {
            if (try? String(contentsOf: last.url, encoding: .utf8)) == text { return last.url }
            if reason == "edit", Date().timeIntervalSince(last.date) < editInterval { return nil }
        }
        let f = folder(rel)
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        let dest = Drop.unique(f.appendingPathComponent("\(stamp.string(from: Date()))--\(reason).md"), ifExists: true)
        guard (try? text.write(to: dest, atomically: true, encoding: .utf8)) != nil else { return nil }
        for old in list(rel).dropFirst(keepPerNote) { try? FileManager.default.removeItem(at: old.url) }
        return dest
    }

    /// Newest first.
    static func list(_ relPath: String) -> [Version] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder(relPath), includingPropertiesForKeys: nil)) ?? []
        return items.compactMap { u -> Version? in
            let parts = u.deletingPathExtension().lastPathComponent.components(separatedBy: "--")
            guard let d = stamp.date(from: String(parts[0].prefix(15))) else { return nil }
            let reason = parts.count > 1 ? parts[1].replacingOccurrences(of: #"-\d+$"#, with: "", options: .regularExpression) : ""
            return Version(url: u, date: d, reason: reason)
        }.sorted { $0.date > $1.date }
    }

    /// Puts an earlier copy back, keeping the current text as a version first.
    static func restore(_ v: Version, to url: URL) throws {
        snapshot(url, reason: "before-restore")
        try String(contentsOf: v.url, encoding: .utf8).write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: filing log and undo

struct FilingRecord: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var title: String
    var target: String
    var action: String
    var original: String?
    /// The copy taken before filing; nil when the note was new.
    var snapshot: String?
    /// SHA-256 of the note right after filing: undo only reverts a note nobody has changed since.
    var after: String
    /// What filing wrote (the entry, or the whole new note).
    var addition: String
    /// The inbox proposal, so undo can put it back.
    var proposal: [String: String]
    var proposalBody: String
    var rule: String?
    var undone = false
}

enum FilingLog {
    static var url: URL { Config.stateDir.appendingPathComponent("filings.json") }
    static let keep = 200

    static func load() -> [FilingRecord] {
        guard let d = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return ((try? dec.decode([FilingRecord].self, from: d)) ?? []).sorted { $0.date > $1.date }
    }

    static func save(_ rs: [FilingRecord]) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? enc.encode(Array(rs.prefix(keep))).write(to: url, options: .atomic)
    }

    static func add(_ r: FilingRecord) { save([r] + load()) }

    static func hash(_ s: String) -> String { hashData(Data(s.utf8)) }

    static func hashData(_ d: Data) -> String {
        SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    }

    /// Reverts a filing and puts its proposal back in the inbox. A note edited
    /// since is left alone unless the filed entry can be taken out on its own.
    static func undo(_ id: UUID) throws -> String {
        var rs = load()
        guard let i = rs.firstIndex(where: { $0.id == id }) else { throw MacKBError("no such filing") }
        guard !rs[i].undone else { throw MacKBError("already undone") }
        let r = rs[i]
        let dest = Config.vault.appendingPathComponent(r.target)
        if let now = try? String(contentsOf: dest, encoding: .utf8) {
            if hash(now) == r.after {
                if let s = r.snapshot {
                    Versions.snapshot(dest, reason: "before-undo")
                    try String(contentsOf: URL(fileURLWithPath: s), encoding: .utf8).write(to: dest, atomically: true, encoding: .utf8)
                } else {
                    try FileManager.default.trashItem(at: dest, resultingItemURL: nil)
                }
            } else if r.snapshot != nil, now.components(separatedBy: r.addition).count == 2 {
                // Edited since, but the entry is still there once: take out just that.
                Versions.snapshot(dest, reason: "before-undo")
                let out = now.replacingOccurrences(of: r.addition, with: "")
                    .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
                try out.write(to: dest, atomically: true, encoding: .utf8)
            } else {
                throw MacKBError("\(r.target) changed after it was filed; open its History to go back to an earlier copy")
            }
        }
        var meta = r.proposal
        meta["undone"] = Drop.dayString(mackb.today())
        let slug = slugify(r.title).isEmpty ? "filing" : slugify(r.title)
        let path = Drop.unique(Config.inboxDir.appendingPathComponent("\(Drop.dayString(mackb.today()).replacingOccurrences(of: "-", with: ""))-\(slug).md"), ifExists: true)
        try Note(path: path, meta: meta, body: r.proposalBody).write()
        rs[i].undone = true
        save(rs)
        return "Undid filing to \(r.target); the proposal is back in the inbox."
    }
}

// MARK: properties

/// Note properties (frontmatter) worth showing as table columns: everything
/// but bookkeeping keys.
enum Properties {
    static let hidden: Set<String> = ["title", "kind", "proposed_by", "proposed", "approved", "tags", "aliases", "privacy_flags"]

    static func of(_ n: Note) -> [String: String] { n.meta.filter { !hidden.contains($0.key) && !$0.value.isEmpty } }

    /// Property names: lowercase words joined by "_".
    static func key(_ k: String) -> String {
        k.lowercased().trimmingCharacters(in: .whitespaces)
            .map { $0.isLetter || $0.isNumber ? $0 : "_" }.reduce("") { $0 + String($1) }
            .replacingOccurrences(of: #"_+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Notes grouped by their `type` property, for the Tables view.
    static func byType(_ notes: [Note]) -> [String: [Note]] {
        Dictionary(grouping: notes.filter { !($0.meta["type"] ?? "").isEmpty && !$0.relPath.hasPrefix("@") },
                   by: { $0.meta["type"]!.lowercased() })
    }

    /// Column order for a group: date first, then the most common keys.
    static func columns(_ notes: [Note]) -> [String] {
        var counts: [String: Int] = [:]
        for n in notes { for k in of(n).keys where k != "type" { counts[k, default: 0] += 1 } }
        let first = ["date", "amount", "provider", "from", "person", "status", "follow_up"]
        return counts.keys.sorted { a, b in
            let ia = first.firstIndex(of: a) ?? 99, ib = first.firstIndex(of: b) ?? 99
            return ia != ib ? ia < ib : (counts[a]! != counts[b]! ? counts[a]! > counts[b]! : a < b)
        }
    }
}

// MARK: follow-ups

/// An open task with a due date, written the way Obsidian's Tasks plugin
/// writes them: `- [ ] Book the cleaning 📅 2027-05-03`.
struct FollowUp: Identifiable {
    var note: Note
    var raw: String
    var text: String
    var due: String
    var id: String { note.relPath + "|" + raw }
    var overdue: Bool { due < Drop.dayString(mackb.today()) }
}

enum Upcoming {
    /// Overdue items and anything due within this many days.
    static let horizonDays = 60
    static let pattern = #"^\s*[-*] \[ \] (.+?)\s*📅\s*(\d{4}-\d{2}-\d{2})"#

    static func scan(_ notes: [Note]) -> [FollowUp] {
        let re = try! NSRegularExpression(pattern: pattern)
        let horizon = Drop.dayString(Calendar.current.date(byAdding: .day, value: horizonDays, to: mackb.today())!)
        var out: [FollowUp] = []
        for n in notes where !n.relPath.hasPrefix("@") {
            for line in n.body.components(separatedBy: "\n") where line.contains("📅") {
                let ns = line as NSString
                guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
                let due = ns.substring(with: m.range(at: 2))
                guard due <= horizon else { continue }
                out.append(FollowUp(note: n, raw: line, text: ns.substring(with: m.range(at: 1)), due: due))
            }
        }
        return out.sorted { $0.due < $1.due }
    }

    /// Ticks it off in its note (Tasks format: `- [x] … ✅ date`).
    static func complete(_ f: FollowUp) throws {
        let text = try String(contentsOf: f.note.path, encoding: .utf8)
        guard let r = text.range(of: f.raw) else { throw MacKBError("that follow-up changed in \(f.note.relPath)") }
        Versions.snapshot(f.note.path, reason: "edit")
        var done = f.raw
        if let box = done.range(of: "[ ]") { done.replaceSubrange(box, with: "[x]") }
        done += " ✅ " + Drop.dayString(mackb.today())
        try text.replacingCharacters(in: r, with: done).write(to: f.note.path, atomically: true, encoding: .utf8)
    }

    /// Adds Tasks lines under the note's "## Follow-ups" heading (made if missing).
    static func append(_ items: [(date: String, what: String)], to text: String) -> String {
        let lines = items.map { "- [ ] \($0.what)" + ($0.date.isEmpty ? "" : " 📅 \($0.date)") }
        guard !lines.isEmpty else { return text }
        var all = text.components(separatedBy: "\n")
        if let h = all.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "## follow-ups" }) {
            var end = h + 1
            while end < all.count, all[end].isEmpty || all[end].hasPrefix("- ") || all[end].hasPrefix("* ") {
                if all[end].isEmpty, end + 1 < all.count, !(all[end + 1].hasPrefix("- ") || all[end + 1].hasPrefix("* ")) { break }
                end += 1
            }
            while end > h + 1, all[end - 1].isEmpty { end -= 1 }
            all.insert(contentsOf: (end == h + 1 ? [""] : []) + lines, at: end)
            return all.joined(separator: "\n")
        }
        return text.trimmingCharacters(in: .newlines) + "\n\n## Follow-ups\n\n" + lines.joined(separator: "\n") + "\n"
    }
}

// MARK: related notes

struct RelatedNote: Identifiable {
    var relPath: String
    var title: String
    var score: Float
    var snippet: String
    var id: String { relPath }
}

enum Related {
    /// Notes whose passages sit closest to this note's, by the search embeddings
    /// already in the index (the note's passages averaged into one vector).
    static func find(_ relPath: String, limit: Int = 12) throws -> [RelatedNote] {
        let idx = try Index()
        let vs = try idx.vectors(of: relPath)
        guard let dim = vs.first?.count, dim > 0 else { return [] }
        var mean = [Float](repeating: 0, count: dim)
        for v in vs where v.count == dim { for i in 0..<dim { mean[i] += v[i] } }
        let norm = sqrt(mean.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return [] }
        mean = mean.map { $0 / norm }
        var best: [String: RelatedNote] = [:]
        for (score, c) in try idx.vectorScored(mean, limit: 300) {
            let p = c.relPath
            guard p != relPath, !p.hasPrefix("@"), !p.lowercased().hasSuffix("readme.md") else { continue }
            if (best[p]?.score ?? -1) < score {
                let snip = c.text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                best[p] = RelatedNote(relPath: p, title: c.title, score: score, snippet: String(snip.prefix(160)))
            }
        }
        return best.values.sorted { $0.score > $1.score }.prefix(limit).map { $0 }
    }
}

// MARK: filing rules

struct FilingRule: Equatable {
    /// A phrase the document contains (a business, clinic or sender).
    var match: String
    /// A note for "append"; a folder for "new" (the model names the note).
    var target: String
    var action: String
    /// File without asking (it can still be undone).
    var auto: Bool
}

enum Rules {
    static var url: URL { Config.stateDir.appendingPathComponent("filing-rules.md") }
    static var candidatesURL: URL { Config.stateDir.appendingPathComponent("filing-rule-candidates.json") }
    /// Approvals of the same sender to the same place before a rule is suggested.
    static let suggestAfter = 3

    static let header = """
    # Filing rules

    Checked before the model decides where a dropped document goes. When a document mentions the phrase in the first column, it is filed there: to that note ("append"), or as a new note in that folder ("new"). The model still writes the entry. Set Auto to "yes" to file without asking; every filing can be undone from the Inbox.

    | When the document mentions | File to | As | Auto |
    | --- | --- | --- | --- |
    """

    static func load() -> [FilingRule] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.components(separatedBy: "\n").compactMap { line -> FilingRule? in
            guard line.hasPrefix("|") else { return nil }
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 3, !cells[0].isEmpty, !cells[0].hasPrefix("---"), cells[0] != "When the document mentions" else { return nil }
            let action = cells[2].lowercased().hasPrefix("new") ? "new" : "append"
            let auto = cells.count > 3 && ["yes", "y", "true", "auto"].contains(cells[3].lowercased())
            return FilingRule(match: cells[0], target: cells[1].trimmingCharacters(in: CharacterSet(charactersIn: "`")), action: action, auto: auto)
        }
    }

    static func add(_ r: FilingRule) throws {
        var text = (try? String(contentsOf: url, encoding: .utf8)) ?? header + "\n"
        if !text.hasSuffix("\n") { text += "\n" }
        text += "| \(r.match) | \(r.target) | \(r.action) | \(r.auto ? "yes" : "no") |\n"
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The rule whose phrase the document mentions; the longest phrase wins.
    static func match(_ text: String, name: String) -> FilingRule? {
        let hay = (name + "\n" + text).lowercased()
        return load().filter { $0.match.count >= 3 && hay.contains($0.match.lowercased()) }.max { $0.match.count < $1.match.count }
    }

    struct Candidate: Codable, Identifiable, Equatable {
        var from: String
        var target: String
        var action: String
        var count: Int
        var dismissed = false
        var id: String { from.lowercased() + "→" + target }
    }

    static func candidates() -> [Candidate] {
        guard let d = try? Data(contentsOf: candidatesURL) else { return [] }
        return (try? JSONDecoder().decode([Candidate].self, from: d)) ?? []
    }

    static func saveCandidates(_ cs: [Candidate]) {
        try? FileManager.default.createDirectory(at: candidatesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(cs).write(to: candidatesURL, options: .atomic)
    }

    /// Counts an approval: same sender, same place. "new" filings count the folder.
    static func record(from: String, target: String, action: String) {
        let from = from.trimmingCharacters(in: .whitespacesAndNewlines)
        guard from.count >= 3 else { return }
        let place = action == "new" ? (target as NSString).deletingLastPathComponent : target
        guard !place.isEmpty else { return }
        var cs = candidates()
        if let i = cs.firstIndex(where: { $0.from.lowercased() == from.lowercased() && $0.target == place && $0.action == action }) {
            cs[i].count += 1
        } else {
            cs.append(Candidate(from: from, target: place, action: action, count: 1))
        }
        saveCandidates(cs)
    }

    /// Senders filed to the same place often enough to offer a rule.
    static func suggestions() -> [Candidate] {
        let have = Set(load().map { $0.match.lowercased() })
        return candidates().filter { $0.count >= suggestAfter && !$0.dismissed && !have.contains($0.from.lowercased()) }
    }

    static func dismiss(_ c: Candidate) {
        var cs = candidates()
        if let i = cs.firstIndex(where: { $0.id == c.id }) { cs[i].dismissed = true }
        saveCandidates(cs)
    }
}
