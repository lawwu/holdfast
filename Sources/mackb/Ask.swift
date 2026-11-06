import Foundation
import NaturalLanguage

struct Answer {
    var text: String
    /// [n] markers in the text that point at no passage.
    var badCitations: [Int] = []
    var sources: [Chunk]
    var stats: GenStats
    var retrievalSeconds: Double
    /// Research mode: the tool calls made, in order.
    var steps: [String] = []
}

/// Collects streamed tokens from a @Sendable callback.
final class TextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buf = ""
    func append(_ s: String) { lock.lock(); buf += s; lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return buf }
}

func citation(_ c: Chunk) -> String { "[[\(c.noteId)#\(c.anchor)]]" }

func ask(_ question: String, embedder: Embedder?, llm: LLMBackend = OllamaBackend(),
         stream: (@Sendable (String) -> Void)? = nil) async throws -> Answer {
    let t0 = Date()
    let hits = try await search(question, embedder: embedder, reranker: await Reranker.shared(), limit: Config.contextChunks)
    let rt = Date().timeIntervalSince(t0)
    guard !hits.isEmpty else {
        // Abstain before generating: nothing relevant enough, so don't ask the 27B to guess.
        let msg = Profile.vaultDefault.notCovered
        stream?(msg)
        return Answer(text: msg, sources: [],
                      stats: GenStats(promptTokens: 0, promptSeconds: 0, outputTokens: 0, outputSeconds: 0), retrievalSeconds: rt)
    }
    var ctx = ""
    for (i, c) in hits.enumerated() {
        ctx += "[\(i + 1)] (\(c.title) — \(c.anchor))\n\(c.text)\n\n"
    }
    var manuals = ""
    for m in Manuals.forPassages(hits) {
        manuals += "Folder manual — \(m.path):\n\(m.text)\n\n"
    }
    let profile = Profile.forPassages(hits)
    let user = (manuals.isEmpty ? "" : manuals + "---\n\n") + "Passages:\n\n\(ctx)Question: \(question)"
    let system = profile.systemPrompt + "\n\n" + todayLine()
    let box = TextBox()
    let stats = try await llm.chat(system: system, user: user) { tok in
        box.append(tok)
        stream?(tok)
    }
    // Citation check: every [n] must point at a passage that was given.
    let cited = (try? NSRegularExpression(pattern: #"\[(\d+)\]"#))?
        .matches(in: box.text, range: NSRange(box.text.startIndex..., in: box.text))
        .compactMap { Range($0.range(at: 1), in: box.text).flatMap { Int(box.text[$0]) } } ?? []
    let bad = Array(Set(cited.filter { $0 < 1 || $0 > hits.count })).sorted()
    return Answer(text: stripThoughts(box.text), badCitations: bad, sources: hits, stats: stats, retrievalSeconds: rt)
}

func formatSources(_ a: Answer) -> String {
    var s = "\nSources:\n"
    for (i, c) in a.sources.enumerated() { s += "  [\(i + 1)] \(citation(c))  — \(c.relPath)\n" }
    return s
}

// MARK: - Agent memory with an approval inbox

/// Cheap privacy lint for anything an agent proposes to save: likely full
/// names, emails and phone numbers. The counselor sees the flags before approving.
func privacyFlags(_ text: String, names: Bool = true) -> [String] {
    var flags: [String] = []
    if text.range(of: #"[\w.+-]+@[\w-]+\.[\w.]+"#, options: .regularExpression) != nil { flags.append("email address") }
    if text.range(of: #"\(?\d{3}\)?[ .-]\d{3}[ .-]\d{4}"#, options: .regularExpression) != nil { flags.append("phone number") }
    // Long digit runs (account, card, member or policy numbers); dates and money don't match.
    let undated = text.replacingOccurrences(of: #"\b\d{4}-\d{2}-\d{2}\b"#, with: " ", options: .regularExpression)
    if undated.range(of: #"\b(?:\d[ -]?){8,}\b"#, options: .regularExpression) != nil { flags.append("long number (account or id?)") }
    guard names else { return Array(Set(flags)).sorted() }
    let name = try! NSRegularExpression(pattern: #"\b([A-Z][a-z]{2,})\s+([A-Z][a-z]{2,})\b"#)
    let allow: Set<String> = ["Holy Spirit", "Jesus Christ", "Old Testament", "New Testament", "Lord Jesus",
                              "Put Off", "Put On", "Inner Man", "Heart Map", "Phase Three", "Case Study"]
    let r = NSRange(text.startIndex..., in: text)
    for m in name.matches(in: text, range: r) {
        let s = String(text[Range(m.range, in: text)!])
        let first = String(text[Range(m.range(at: 1), in: text)!])
        let books: Set<String> = ["First", "Second", "Third", "Song", "God", "The", "This", "That", "When", "And", "But", "Lord"]
        if allow.contains(s) || books.contains(first) { continue }
        flags.append("possible name: \"\(s)\"")
    }
    flags += nameTaggerFlags(text)
    return Array(Set(flags)).sorted()
}

/// Apple's on-device named-entity tagger (no download): personal names that are
/// not initials and not common biblical names (oss-best-practices.md #10).
func nameTaggerFlags(_ text: String) -> [String] {
    let biblical: Set<String> = ["God", "Jesus", "Christ", "Lord", "Holy Spirit", "Paul", "Peter", "John", "James", "Moses",
        "David", "Abraham", "Isaac", "Jacob", "Joseph", "Mary", "Martha", "Matthew", "Mark", "Luke", "Timothy", "Titus",
        "Solomon", "Job", "Elijah", "Isaiah", "Jeremiah", "Daniel", "Jonah", "Ruth", "Esther", "Noah", "Adam", "Eve",
        "Samuel", "Saul", "Ezekiel", "Philippians", "Ephesians", "Colossians", "Corinthians", "Romans", "Galatians", "Hebrews"]
    let tagger = NLTagger(tagSchemes: [.nameType])
    tagger.string = text
    var out: [String] = []
    tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                         options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, range in
        if tag == .personalName {
            let name = String(text[range])
            if !biblical.contains(name), name.range(of: #"^([A-Z]\.?){1,3}$"#, options: .regularExpression) == nil {
                out.append("possible name: \"\(name)\"")
            }
        }
        return true
    }
    return out
}

func propose(title: String, text: String, tags: [String], by agent: String) throws -> (Note, [String]) {
    try ensureVault()
    let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone(identifier: "America/Los_Angeles")!,
                                            formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime])
    let flags = privacyFlags(title + "\n" + text)
    var meta = ["title": title, "kind": "memory", "proposed_by": agent, "proposed": stamp]
    if !tags.isEmpty { meta["tags"] = tags.joined(separator: ", ") }
    if !flags.isEmpty { meta["privacy_flags"] = flags.joined(separator: "; ") }
    let slug = slugify(title).isEmpty ? "memory" : slugify(title)
    let path = Config.inboxDir.appendingPathComponent("\(stamp.prefix(10).replacingOccurrences(of: "-", with: ""))-\(slug).md")
    let note = Note(path: path, meta: meta, body: "\n# \(title)\n\n\(text)\n")
    try note.write()
    return (note, flags)
}

func inbox() -> [Note] { allNotes(in: [Config.inboxDir]) }

func approve(_ id: String) throws -> Note {
    guard let n = inbox().first(where: { $0.id == id }) else { throw MacKBError("no inbox item \(id)") }
    if n.meta["kind"] == "filing" {  // a dropped file: write it where the model proposed
        let dest = try Drop.apply(n)
        try FileManager.default.removeItem(at: n.path)
        // Learn: the same sender approved to the same place often enough becomes a suggested rule.
        if n.meta["rule"] == nil, let from = n.meta["from"], let action = n.meta["action"] {
            Rules.record(from: from, target: Drop.relative(dest), action: action)
        }
        return (try? Note.read(dest)) ?? Note(path: dest, meta: [:], body: "")
    }
    var m = n
    m.meta["approved"] = ISO8601DateFormatter.string(from: Date(), timeZone: TimeZone(identifier: "America/Los_Angeles")!, formatOptions: [.withFullDate])
    m.path = Config.memoryDir.appendingPathComponent(n.path.lastPathComponent)
    try m.write()
    try FileManager.default.removeItem(at: n.path)
    return m
}

func reject(_ id: String) throws {
    guard let n = inbox().first(where: { $0.id == id }) else { throw MacKBError("no inbox item \(id)") }
    // Rejected proposals go to the Trash, not oblivion.
    try FileManager.default.trashItem(at: n.path, resultingItemURL: nil)
}

/// Gemma 4 sometimes emits an empty thought channel even with thinking off:
/// "<|channel>thought …<channel|>". Keep only what follows it.
func stripThoughts(_ s: String) -> String {
    var s = s
    // gpt-oss (harmony format): reasoning in the analysis channel, the answer in "final".
    if let r = s.range(of: "<|channel|>final<|message|>", options: .backwards) { s = String(s[r.upperBound...]) }
    else if s.hasPrefix("analysis"), let r = s.range(of: "assistantfinal", options: .backwards) { s = String(s[r.upperBound...]) }
    s = s.replacingOccurrences(of: "<|return|>", with: "").replacingOccurrences(of: "<|end|>", with: "")
    return s.replacingOccurrences(of: #"<\|channel\>[\s\S]*?<channel\|>"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
