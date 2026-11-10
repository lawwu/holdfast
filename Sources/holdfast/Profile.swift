import Foundation

/// How the app talks about a part of the vault: the answer prompt, the
/// reranker's instruction, the suggested questions and the "not covered" reply.
/// Private notes carry stricter handling rules throughout the app.
struct Profile: Equatable {
    let id: String
    let name: String
    let systemPrompt: String
    let rerankInstruction: String
    let notCovered: String
    let suggestions: [(icon: String, text: String)]

    static func == (a: Profile, b: Profile) -> Bool { a.id == b.id }

    static let general = Profile(
        id: "general", name: "General knowledge base",
        systemPrompt: """
        You answer questions from the user's own knowledge base: notes, logs, plans and \
        generated reports. Answer ONLY from the numbered passages provided. After each claim, \
        cite the passage it came from as [n]. Folder manuals, when given, explain how that part \
        of the knowledge base is organized and any rules for answering there: follow them, and \
        use them to say which file would hold an answer the passages lack. Reports marked \
        GENERATED are the source for numbers; hand-written notes are the source for goals and \
        context. Use today's date to judge what is past, current or upcoming. If the passages \
        do not answer the question, say so plainly instead of guessing. Be concise.
        """,
        rerankInstruction: "Given a question, judge whether this passage from the user's own notes and records answers it",
        notCovered: "Your notes don't cover this question. Nothing in the vault was relevant enough to answer from.",
        suggestions: [
            ("calendar", "What's coming up in the next few weeks?"),
            ("checklist", "What open items are still on my lists?"),
            ("arrow.triangle.2.circlepath", "What changed most recently, and where is it recorded?"),
            ("target", "What goals have I written down, and how am I doing on them?"),
        ])

    static let privateNotes = Profile(
        id: "private", name: "Private notes (this Mac only)",
        systemPrompt: """
        You help the user search their private notes, records and reports. \
        Answer ONLY from the numbered passages provided. \
        After each claim, cite the passage it came from as [n]. If the passages do not answer the \
        question, say so plainly instead of guessing. Refer to participants by initials only, never \
        full names, even if a passage spells one out. Quote references exactly as the passages \
        give them. Be concise and practical.
        """,
        rerankInstruction: "Given a question, judge whether this passage from the user's private notes or reports answers it",
        notCovered: "Your materials don't cover this question. Nothing in the vault was relevant enough to answer from.",
        suggestions: [
            ("list.bullet.clipboard", "What follow-ups are recorded across these notes?"),
            ("arrow.triangle.2.circlepath", "What has changed across the sessions?"),
            ("book.closed", "Which references were recorded, and when?"),
            ("lightbulb", "What did I note I could have done better?"),
        ])

    static let all = [general, privateNotes]

    /// The vault's default, chosen in Settings. Until then: a managed vault is
    /// private by default; a folder indexed in place is general.
    static var vaultDefault: Profile {
        get {
            let id = LegacyCompatibility.profileID(UserDefaults.standard.string(forKey: "profile:" + Config.vault.path))
            return all.first { $0.id == id } ?? (Config.inPlace ? general : privateNotes)
        }
        set { UserDefaults.standard.set(newValue.id, forKey: "profile:" + Config.vault.path) }
    }

    private static func protectedFolder(_ top: String) -> Bool {
        top.hasPrefix("private") || top.hasPrefix("confidential") || LegacyCompatibility.isProtectedFolder(top)
    }

    /// Private and confidential top-level folders always use the private profile.
    static func forPath(_ relPath: String) -> Profile {
        let top = relPath.split(separator: "/").first.map { $0.lowercased() } ?? ""
        if protectedFolder(top) { return privateNotes }
        return vaultDefault
    }

    /// Private material: under a private/cases folder, or anywhere in a private vault.
    /// It stays on this Mac, is never filed by a rule, and is never cross-linked.
    static func isPrivate(_ relPath: String) -> Bool {
        let top = relPath.split(separator: "/").first.map { $0.lowercased() } ?? ""
        return protectedFolder(top) || vaultDefault.id == privateNotes.id
    }

    /// Ignore macOS's /private filesystem root when checking an imported file's folders.
    static func isPrivateSource(_ url: URL) -> Bool {
        var parts = url.standardizedFileURL.pathComponents
        if parts.starts(with: ["/", "private"]) { parts.removeFirst(2) }
        return parts.contains(where: isPrivate)
    }

    /// The profile most of the retrieved passages belong to.
    static func forPassages(_ hits: [Chunk]) -> Profile {
        let counts = Dictionary(grouping: hits.map { forPath($0.relPath) }, by: \.id).mapValues(\.count)
        let id = counts.max { $0.value < $1.value }?.key
        return all.first { $0.id == id } ?? vaultDefault
    }
}

/// Today's date line for prompts, in the vault's timezone.
func todayLine() -> String {
    let f = DateFormatter()
    f.timeZone = TimeZone(identifier: "America/Los_Angeles")
    f.dateFormat = "EEEE, MMMM d, yyyy"
    return "Today is \(f.string(from: today())) (America/Los_Angeles)."
}

/// Now, or HOLDFAST_TODAY (YYYY-MM-DD) so evals over a fixture give the same answers any day.
func today() -> Date {
    if let s = ProcessInfo.processInfo.environment["HOLDFAST_TODAY"] {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        if let d = f.date(from: s + " 12:00") { return d }
    }
    return Date()
}

/// Folder manuals: for an in-place vault, the README.md of the top-level
/// folders the passages come from (most passages first, at most two), cut at
/// a paragraph near `Manuals.maxChars`. They tell the model how that part of
/// the vault is organized, as a domain README tells Claude Code in a repo.
enum Manuals {
    static let maxDomains = 2
    static let maxChars = 3000

    static func forPassages(_ hits: [Chunk]) -> [(path: String, text: String)] {
        guard Config.inPlace else { return [] }
        var counts: [String: Int] = [:]
        var order: [String] = []
        for h in hits {
            let parts = h.relPath.split(separator: "/")
            guard parts.count > 1, !h.relPath.hasPrefix("@") else { continue }
            let d = String(parts[0])
            if counts[d] == nil { order.append(d) }
            counts[d, default: 0] += 1
        }
        let domains = order.sorted { counts[$0]! > counts[$1]! }.prefix(maxDomains)
        return domains.compactMap { d in
            let rel = "\(d)/README.md"
            guard let text = try? String(contentsOf: Config.vault.appendingPathComponent(rel), encoding: .utf8) else { return nil }
            return (rel, cut(text))
        }
    }

    static func cut(_ s: String) -> String {
        guard s.count > maxChars else { return s }
        let head = String(s.prefix(maxChars))
        let end = head.range(of: "\n\n", options: .backwards)?.lowerBound ?? head.endIndex
        return String(head[..<end]) + "\n\n[… manual continues]"
    }
}

extension Profile: Hashable {
    func hash(into h: inout Hasher) { h.combine(id) }
}
