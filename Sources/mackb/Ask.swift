import Foundation

/// The Q&A prompt is written for the first use case: a biblical counselor asking
/// questions of their own materials and past case reports.
let askSystemPrompt = """
You help a biblical counselor search their own counseling materials: lessons, homework, \
supervision notes and past case reports. Answer ONLY from the numbered passages provided. \
After each claim, cite the passage it came from as [n]. If the passages do not answer the \
question, say so plainly instead of guessing. Refer to counselees by initials only, never \
full names, even if a passage spells one out. Quote Scripture references exactly as the \
passages give them. Be concise and practical. You are preparing the counselor, not \
counseling anyone yourself.
"""

struct Answer {
    var text: String
    var sources: [Chunk]
    var stats: GenStats
    var retrievalSeconds: Double
}

func citation(_ c: Chunk) -> String { "[[\(c.noteId)#\(c.anchor)]]" }

func ask(_ question: String, embedder: Embedder?, llm: LLMBackend = OllamaBackend(),
         stream: ((String) -> Void)? = nil) async throws -> Answer {
    let t0 = Date()
    let hits = try await search(question, embedder: embedder, limit: Config.contextChunks)
    let rt = Date().timeIntervalSince(t0)
    guard !hits.isEmpty else {
        return Answer(text: "Nothing in the vault matches that question.", sources: [],
                      stats: GenStats(promptTokens: 0, promptSeconds: 0, outputTokens: 0, outputSeconds: 0), retrievalSeconds: rt)
    }
    var ctx = ""
    for (i, c) in hits.enumerated() {
        ctx += "[\(i + 1)] (\(c.title) — \(c.anchor))\n\(c.text)\n\n"
    }
    let user = "Passages:\n\n\(ctx)Question: \(question)"
    var text = ""
    let stats = try await llm.chat(system: askSystemPrompt, user: user) { tok in
        text += tok
        stream?(tok)
    }
    return Answer(text: text, sources: hits, stats: stats, retrievalSeconds: rt)
}

func formatSources(_ a: Answer) -> String {
    var s = "\nSources:\n"
    for (i, c) in a.sources.enumerated() { s += "  [\(i + 1)] \(citation(c))  — \(c.relPath)\n" }
    return s
}

// MARK: - Agent memory with an approval inbox

/// Cheap privacy lint for anything an agent proposes to save: likely full
/// names, emails and phone numbers. The counselor sees the flags before approving.
func privacyFlags(_ text: String) -> [String] {
    var flags: [String] = []
    let name = try! NSRegularExpression(pattern: #"\b([A-Z][a-z]{2,})\s+([A-Z][a-z]{2,})\b"#)
    let allow: Set<String> = ["Holy Spirit", "Jesus Christ", "Old Testament", "New Testament", "Lord Jesus",
                              "Put Off", "Put On", "Inner Man", "Heart Map", "Phase Three", "Case Study"]
    let r = NSRange(text.startIndex..., in: text)
    for m in name.matches(in: text, range: r) {
        let s = String(text[Range(m.range, in: text)!])
        let first = String(text[Range(m.range(at: 1), in: text)!])
        let books: Set<String> = ["First", "Second", "Third", "Song", "God", "The", "This", "That", "When", "And", "But", "Lord"]
        if allow.contains(s) || books.contains(first) { continue }
        flags.append("possible full name: \"\(s)\"")
    }
    if text.range(of: #"[\w.+-]+@[\w-]+\.[\w.]+"#, options: .regularExpression) != nil { flags.append("email address") }
    if text.range(of: #"\(?\d{3}\)?[ .-]\d{3}[ .-]\d{4}"#, options: .regularExpression) != nil { flags.append("phone number") }
    return Array(Set(flags)).sorted()
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
