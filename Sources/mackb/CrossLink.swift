import Foundation

// MARK: - Cross-linking job
//
// Suggests "See also" links between notes that belong together but don't link
// yet. Split so a small local model only makes the decision it is good at:
// 1. candidates: the search embeddings pick each note's closest notes (no model);
// 2. judge: the model answers one yes/no question per pair, seeing both notes;
// 3. proposals: each "yes" becomes an Inbox proposal to add a line under the
//    note's "## See also" heading, approved in groups and undoable.

enum CrossLink {
    /// Closest notes considered per note.
    static let perNote = 5
    /// Cosine similarity a pair needs to be judged at all.
    static let minScore: Float = 0.5
    /// Characters of each note the model sees.
    static let noteChars = 1_500

    struct Pair: Codable, Hashable {
        var a: String   // vault path of the note that gets the link
        var b: String   // vault path it links to
        var score: Float
    }

    struct Verdict: Codable {
        var a: String
        var b: String
        var score: Float
        var link: Bool
        var reason: String
        var seconds: Double
        var error: String?
    }

    /// Notes worth linking: in the vault proper, not folder READMEs (they are manuals).
    static func eligible(_ n: Note) -> Bool {
        !n.relPath.hasPrefix("@") && !Packs.isPack(n.relPath) && n.name.lowercased() != "readme"
    }

    /// Pairs of close notes with no link between them, strongest first. Each pair appears once.
    static func candidates(_ notes: [Note], perNote: Int = perNote, minScore: Float = minScore) -> [Pair] {
        let graph = LinkGraph(notes: notes)
        let byPath = Dictionary(notes.map { ($0.relPath, $0) }, uniquingKeysWith: { a, _ in a })
        var best: [Set<String>: Pair] = [:]
        for n in notes where eligible(n) {
            for r in (try? Related.find(n.relPath, limit: perNote)) ?? [] where r.score >= minScore {
                guard let m = byPath[r.relPath], eligible(m) else { continue }
                let linked = (graph.outgoing[n.id] ?? []).contains(m.id) || (graph.outgoing[m.id] ?? []).contains(n.id)
                guard !linked else { continue }
                let key: Set<String> = [n.relPath, m.relPath]
                if (best[key]?.score ?? -1) < r.score { best[key] = Pair(a: n.relPath, b: m.relPath, score: r.score) }
            }
        }
        return best.values.sorted { $0.score > $1.score }
    }

    static let instructions = """
    You help keep a family's notes connected. You see two notes, A and B. Decide whether note A should get a "See also" link to note B.

    Say yes only when someone reading A would want B at hand because they are about the same specific thing: the same person's ongoing situation, the same event or trip, the same appliance, account, policy, provider relationship, project or decision, or one note continues, updates or explains the other.
    Say no when they only share a category (two different recipes, two unrelated purchases, visits by different people for different reasons, two different trips) or a common word.

    Reply with one JSON object and nothing else: {"link": true or false, "reason": "one short sentence naming what they share"}
    """

    static func excerpt(_ n: Note) -> String {
        let body = n.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Path: \(n.relPath)\nTitle: \(n.title)\n\n" + String(body.prefix(noteChars)) + (body.count > noteChars ? "\n[…]" : "")
    }

    /// One yes/no decision.
    static func judge(_ p: Pair, a: Note, b: Note, llm: LLMBackend) async -> Verdict {
        let t0 = Date()
        let out = OutputBuffer()
        do {
            _ = try await llm.chat(system: instructions, user: "Note A\n\(excerpt(a))\n\n---\nNote B\n\(excerpt(b))",
                                   temperature: Config.filingTemperature) { out.append($0) }
            let reply = stripThoughts(out.text)
            var link = false, reason = ""
            if let s = reply.firstIndex(of: "{"), let e = Drop.firstObjectEnd(reply, from: s),
               let obj = try? JSONSerialization.jsonObject(with: Data(reply[s...e].utf8)) as? [String: Any] {
                link = (obj["link"] as? Bool) ?? ((obj["link"] as? String)?.lowercased() == "true")
                reason = obj["reason"] as? String ?? ""
            } else {
                link = reply.range(of: #""link"\s*:\s*true"#, options: .regularExpression) != nil
            }
            return Verdict(a: p.a, b: p.b, score: p.score, link: link, reason: reason, seconds: Date().timeIntervalSince(t0))
        } catch {
            return Verdict(a: p.a, b: p.b, score: p.score, link: false, reason: "", seconds: Date().timeIntervalSince(t0), error: "\(error)")
        }
    }

    /// The line added under "## See also" in A.
    static func line(to b: Note, reason: String) -> String {
        let target = String(b.relPath.dropLast(b.relPath.hasSuffix(".md") ? 3 : 0))
        return "- [[\(target)|\(b.title)]]" + (reason.isEmpty ? "" : " — \(reason)")
    }

    /// An Inbox proposal for a "yes".
    @discardableResult
    static func propose(_ v: Verdict, a: Note, b: Note, model: String) throws -> Note {
        let today = Drop.dayString(mackb.today())
        let meta = ["title": "Link \(a.title) → \(b.title)", "kind": "filing", "action": "link", "target": a.relPath,
                    "why": v.reason, "proposed_by": "Cross-link job · \(model)", "proposed": today]
        let slug = slugify("link " + a.name + " " + b.name)
        let path = Drop.unique(Config.inboxDir.appendingPathComponent("\(today.replacingOccurrences(of: "-", with: ""))-\(slug.prefix(80)).md"), ifExists: true)
        let n = Note(path: path, meta: meta, body: "\n" + line(to: b, reason: v.reason) + "\n")
        try n.write()
        return n
    }

    /// The whole job: candidates, a decision per pair, a proposal per "yes".
    static func run(llm: LLMBackend, model: String, limit: Int? = nil, dryRun: Bool = false,
                    progress: @escaping @Sendable (Int, Int, String) async -> Bool) async -> [Verdict] {
        let notes = allNotes()
        let byPath = Dictionary(notes.map { ($0.relPath, $0) }, uniquingKeysWith: { a, _ in a })
        // Pairs already proposed and waiting in the Inbox aren't asked about again.
        let waiting = Set(inbox().filter { $0.meta["action"] == "link" }.map { ($0.meta["target"] ?? "") + "→" + $0.body })
        var pairs = candidates(notes)
        if let limit { pairs = Array(pairs.prefix(limit)) }
        var out: [Verdict] = []
        for (i, p) in pairs.enumerated() {
            guard let a = byPath[p.a], let b = byPath[p.b] else { continue }
            guard await progress(i, pairs.count, "\(a.title) ↔ \(b.title)") else { break }
            if waiting.contains(where: { $0.hasPrefix(p.a + "→") && $0.contains(String(p.b.dropLast(3))) }) { continue }
            let v = await judge(p, a: a, b: b, llm: llm)
            out.append(v)
            if v.link, !dryRun { try? propose(v, a: a, b: b, model: model) }
        }
        _ = await progress(pairs.count, pairs.count, "")
        return out
    }
}

/// Adds lines under a "## Heading" (made at the end if missing), after its existing list.
func appendUnder(_ heading: String, lines: [String], to text: String) -> String {
    guard !lines.isEmpty else { return text }
    var all = text.components(separatedBy: "\n")
    if let h = all.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == heading.lowercased() }) {
        var end = h + 1
        while end < all.count, all[end].isEmpty || all[end].hasPrefix("- ") || all[end].hasPrefix("* ") {
            if all[end].isEmpty, end + 1 < all.count, !(all[end + 1].hasPrefix("- ") || all[end + 1].hasPrefix("* ")) { break }
            end += 1
        }
        while end > h + 1, all[end - 1].isEmpty { end -= 1 }
        all.insert(contentsOf: (end == h + 1 ? [""] : []) + lines, at: end)
        return all.joined(separator: "\n")
    }
    return text.trimmingCharacters(in: .newlines) + "\n\n\(heading)\n\n" + lines.joined(separator: "\n") + "\n"
}
