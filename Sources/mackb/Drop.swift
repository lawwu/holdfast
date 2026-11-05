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

let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif"]

enum Drop {
    /// Files dropped here get filed. In place it lives with the app state, not in the repo.
    static var dir: URL {
        Config.inPlace ? Config.stateDir.appendingPathComponent("Drop") : Config.vault.appendingPathComponent("drop")
    }
    /// Originals after filing (or a failed attempt), kept out of the vault.
    static var filedDir: URL { Config.stateDir.appendingPathComponent("drop-filed") }

    /// Characters of the dropped document the model sees when filing it.
    static let maxDocChars = 12_000
    /// Related notes listed for the model, found by searching the document's opening.
    static let relatedNotes = 8
    /// Of those, how many are shown in full (so the model can see what is already recorded), and how much of each.
    static let shownNotes = 3
    static let shownChars = 4_000
    /// A file is picked up once it has not changed for this long (still copying otherwise).
    static let settleSeconds: TimeInterval = 3
    /// How often the app looks in the drop folder.
    static let pollSeconds: TimeInterval = 5

    static var supported: Set<String> { docExtensions.union(audioExtensions).union(imageExtensions) }

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
    }

    static let instructions = """
    You file a document that was dropped into this knowledge base. Decide where it belongs and write what should be saved.

    - Follow the folder READMEs below: they say where each kind of thing is recorded (a log, a dated table, one note per item).
    - If a README says events of this kind go in an existing log or note, append to that note ("append"). Otherwise create a new note ("new") in the right folder, named like its neighbours (lowercase, hyphens, dated YYYY-MM-DD or YYYYMM_ prefixes when the folder uses them).
    - Write a short summary and the facts worth finding later: dates, amounts, providers or businesses, decisions, follow-ups. Do not paste the whole document.
    - For "append", write only the lines to add: a table row matching that table's columns, or a dated section.
    - For "new", write the whole note, starting with a "# " title.
    - Never include account numbers, card numbers, policy or member ids, passwords or other credentials.
    - Anything about counseling or the care of a person (ministry folders): initials only, never full names.
    - Dates as YYYY-MM-DD, America/Los_Angeles.
    - If the notes shown below already record this document (same date and event), reply with "action": "skip" and say where in "why".

    Reply with one JSON object and nothing else:
    {"action": "new" | "append" | "skip", "path": "folder/sub/file.md", "title": "…", "markdown": "…", "why": "one sentence: why this place"}
    """

    /// Asks the model where a dropped file belongs; the proposal goes to the inbox.
    static func propose(_ url: URL, text: String, embedder: Embedder?, llm: LLMBackend, model: String) async throws -> (Note, [String]) {
        let doc = String(text.prefix(maxDocChars))
        let probe = url.deletingPathExtension().lastPathComponent + "\n" + String(doc.prefix(1500))
        let hits = (try? await search(probe, embedder: embedder, limit: 24)) ?? []
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
        let user = """
        \(Agent.vaultOverview())
        Notes that look related:
        \(related.isEmpty ? "(none found)" : related.joined(separator: "\n"))

        The closest of those, as they are now:

        \(shown.isEmpty ? "(none)" : shown.joined(separator: "\n\n"))

        Folder READMEs:

        \(manuals.isEmpty ? "(none)" : manuals)

        ---
        Dropped file: \(url.lastPathComponent)\(text.count > maxDocChars ? " (first \(maxDocChars) characters)" : "")

        \(doc)
        """
        let system = [instructions, todayLine()].joined(separator: "\n\n")
        let out = OutputBuffer()
        _ = try await llm.chat(system: system, user: user) { out.append($0) }
        var f = try parse(out.text)
        if f.action.lowercased() == "skip" { throw AlreadyFiled(why: f.why) }
        f = try validate(f)
        if f.title.trimmingCharacters(in: .whitespaces).isEmpty {
            f.title = (f.action == "append" ? "Add to " : "") + (f.path as NSString).lastPathComponent
        }

        let today = dayString(Date())
        // Names matter in counseling folders (initials only); elsewhere a shop or clinic name is the point.
        let counseling = Profile.forPath(f.path).id == Profile.counseling.id
        let flags = privacyFlags(f.title + "\n" + f.markdown, names: counseling)
        var meta = ["title": f.title, "kind": "filing", "proposed_by": "Drop folder · \(model)", "proposed": today,
                    "target": f.path, "action": f.action, "why": f.why, "original": url.lastPathComponent]
        if !flags.isEmpty { meta["privacy_flags"] = flags.joined(separator: "; ") }
        let slug = slugify(f.title).isEmpty ? "filing" : slugify(f.title)
        let path = Config.inboxDir.appendingPathComponent("\(today.replacingOccurrences(of: "-", with: ""))-\(slug).md")
        let note = Note(path: Drop.unique(path, ifExists: true), meta: meta, body: "\n" + f.markdown.trimmingCharacters(in: .whitespacesAndNewlines) + "\n")
        try note.write()
        return (note, flags)
    }

    /// The JSON object in the model's reply (it may wrap it in a code fence).
    static func parse(_ reply: String) throws -> Filing {
        guard let a = reply.firstIndex(of: "{"), let b = reply.lastIndex(of: "}"), a < b,
              let data = String(reply[a...b]).data(using: .utf8) else {
            throw MacKBError("the model's filing reply had no JSON: \(reply.prefix(200))")
        }
        do { return try JSONDecoder().decode(Filing.self, from: data) }
        catch { throw MacKBError("couldn't read the model's filing reply: \(error)") }
    }

    /// Keeps the target inside the vault, a Markdown file, and consistent with the action.
    static func validate(_ f: Filing) throws -> Filing {
        var f = f
        var p = f.path.trimmingCharacters(in: .whitespaces)
        while p.hasPrefix("./") || p.hasPrefix("/") { p.removeFirst(p.hasPrefix("./") ? 2 : 1) }
        let parts = p.split(separator: "/")
        if p.isEmpty || parts.contains("..") || parts.contains(where: { $0.hasPrefix(".") }) {
            throw MacKBError("the model proposed a path outside the vault: \(f.path)")
        }
        if !p.hasSuffix(".md") { p += ".md" }
        f.path = p
        let exists = FileManager.default.fileExists(atPath: Config.vault.appendingPathComponent(p).path)
        f.action = f.action.lowercased() == "append" && exists ? "append" : "new"
        if f.action == "new" && exists {  // never overwrite: pick a free name next to it
            f.path = relative(unique(Config.vault.appendingPathComponent(p)))
        }
        return f
    }

    static func relative(_ u: URL) -> String {
        let root = Config.vault.standardizedFileURL.path + "/"
        let p = u.standardizedFileURL.path
        return p.hasPrefix(root) ? String(p.dropFirst(root.count)) : p
    }

    static func unique(_ url: URL, ifExists: Bool) -> URL {
        FileManager.default.fileExists(atPath: url.path) ? unique(url) : url
    }

    /// Writes an approved filing into the vault. Appends go after the last
    /// line of the note's last table when the addition is a table row,
    /// otherwise at the end of the note.
    static func apply(_ item: Note) throws -> URL {
        guard let target = item.meta["target"] else { throw MacKBError("filing has no target") }
        let dest = Config.vault.appendingPathComponent(target)
        let addition = item.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if item.meta["action"] == "append", var text = try? String(contentsOf: dest, encoding: .utf8) {
            if addition.hasPrefix("|") {
                var lines = text.components(separatedBy: "\n")
                if let last = lines.lastIndex(where: { $0.hasPrefix("|") }) {
                    lines.insert(contentsOf: addition.components(separatedBy: "\n"), at: last + 1)
                    text = lines.joined(separator: "\n")
                } else {
                    text = text.trimmingCharacters(in: .newlines) + "\n\n" + addition + "\n"
                }
            } else {
                text = text.trimmingCharacters(in: .newlines) + "\n\n" + addition + "\n"
            }
            try text.write(to: dest, atomically: true, encoding: .utf8)
        } else {
            let dest = FileManager.default.fileExists(atPath: dest.path) ? unique(dest) : dest
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (addition + "\n").write(to: dest, atomically: true, encoding: .utf8)
            return dest
        }
        return dest
    }

    static func dayString(_ d: Date) -> String {
        ISO8601DateFormatter.string(from: d, timeZone: TimeZone(identifier: "America/Los_Angeles")!, formatOptions: [.withFullDate])
    }

    /// Files one dropped file. Managed vaults import it; in-place vaults get a
    /// proposal in the inbox. The original leaves the drop folder either way.
    static func process(_ url: URL, embedder: Embedder?, llm: LLMBackend?, model: String) async throws -> String {
        defer { _ = try? moveToFiled(url) }
        if !Config.inPlace {
            if audioExtensions.contains(url.pathExtension.lowercased()) {
                let n = try await ingestAudio(url, title: nil, tags: [])
                return "Imported \(n.title)"
            }
            let n = try ingestDocument(url, root: nil, tags: [])
            return "Imported \(n.title)"
        }
        let text = try await self.text(of: url)
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 else {
            throw MacKBError("\(url.lastPathComponent): no readable text")
        }
        guard let llm else { throw MacKBError("no model loaded to file \(url.lastPathComponent)") }
        let (n, _) = try await propose(url, text: text, embedder: embedder, llm: llm, model: model)
        return "Proposed \(n.meta["target"] ?? "")"
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
        throw MacKBError("can't open image \(url.lastPathComponent)")
    }
    // Flatten onto white: Vision reads dark text on a transparent background as nothing.
    let w = src.width, h = src.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw MacKBError("can't read image \(url.lastPathComponent)")
    }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let cg = ctx.makeImage() else { throw MacKBError("can't read image \(url.lastPathComponent)") }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = true
    try VNImageRequestHandler(cgImage: cg).perform([req])
    return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}
