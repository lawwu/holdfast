import Foundation

/// Links between notes: Obsidian `[[wikilinks]]` (with `#heading` and `|alias`)
/// and relative Markdown links to `.md` files, as many Markdown repos do.
struct NoteLink: Hashable {
    var target: String  // as written
    var heading: String?
    var label: String
    var wiki: Bool
}

enum LinkParser {
    static let wiki = try! NSRegularExpression(pattern: #"\[\[([^\[\]|#]+)(?:#([^\[\]|]*))?(?:\|([^\[\]]*))?\]\]"#)
    /// [label](relative/path.md#heading); skips URLs with a scheme.
    static let md = try! NSRegularExpression(pattern: #"\[([^\]]*)\]\((?![a-zA-Z][a-zA-Z0-9+.-]*:)([^)\s#]+\.md)(?:#([^)\s]*))?\)"#)

    static func links(in text: String) -> [NoteLink] {
        var out: [NoteLink] = []
        let ns = text as NSString
        let all = NSRange(location: 0, length: ns.length)
        for m in wiki.matches(in: text, range: all) {
            let t = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let h = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : nil
            let a = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : nil
            out.append(NoteLink(target: t, heading: h, label: a ?? t, wiki: true))
        }
        for m in md.matches(in: text, range: all) {
            let raw = ns.substring(with: m.range(at: 2))
            let t = raw.removingPercentEncoding ?? raw
            let h = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : nil
            out.append(NoteLink(target: t, heading: h, label: ns.substring(with: m.range(at: 1)), wiki: false))
        }
        return out
    }
}

/// Every note's outgoing and incoming links, rebuilt from the vault on load
/// and after a save (a few hundred notes take milliseconds).
struct LinkGraph {
    var byId: [String: Note] = [:]
    /// note id → ids it links to (resolved only), in order, without repeats.
    var outgoing: [String: [String]] = [:]
    /// note id → ids that link to it.
    var incoming: [String: [String]] = [:]
    /// note id → link targets that resolve to no note.
    var unresolved: [String: [String]] = [:]
    private var byName: [String: [Note]] = [:]

    init() {}

    init(notes: [Note]) {
        for n in notes {
            byId[n.id] = n
            byName[n.name.lowercased(), default: []].append(n)
            byName[n.title.lowercased(), default: []].append(n)
        }
        for n in notes {
            var seen = Set<String>()
            for l in LinkParser.links(in: n.body) {
                if let t = resolve(l, from: n) {
                    guard t.id != n.id, seen.insert(t.id).inserted else { continue }
                    outgoing[n.id, default: []].append(t.id)
                    incoming[t.id, default: []].append(n.id)
                } else if l.wiki {
                    unresolved[n.id, default: []].append(l.target)
                }
            }
        }
    }

    /// Resolve a link written in `from`. Markdown links are relative to the
    /// note's folder; wikilinks match a vault path, then a file name or title
    /// (preferring the same folder, then the shortest path), like Obsidian.
    func resolve(_ l: NoteLink, from: Note) -> Note? {
        if !l.wiki {
            let base = from.path.deletingLastPathComponent()
            let url = URL(fileURLWithPath: l.target, relativeTo: base).standardizedFileURL
            return byId.values.first { $0.path.standardizedFileURL.path == url.path }
        }
        return resolve(wikiTarget: l.target, from: from)
    }

    func resolve(wikiTarget raw: String, from: Note?) -> Note? {
        let t = raw.hasSuffix(".md") ? String(raw.dropLast(3)) : raw
        if let n = byId[t] { return n }
        let key = (t as NSString).lastPathComponent.lowercased()
        guard let cands = byName[key], !cands.isEmpty else { return nil }
        if t.contains("/") {
            if let n = cands.first(where: { $0.id.lowercased().hasSuffix(t.lowercased()) }) { return n }
        }
        if let from {
            let dir = from.path.deletingLastPathComponent().path
            if let n = cands.first(where: { $0.path.deletingLastPathComponent().path == dir }) { return n }
        }
        return cands.min { $0.relPath.count < $1.relPath.count }
    }

    /// Lines in `source` that link to `target`, for the backlinks panel.
    func mentions(of target: Note, in source: Note) -> [String] {
        source.body.split(separator: "\n").map(String.init).filter { line in
            LinkParser.links(in: line).contains { resolve($0, from: source)?.id == target.id }
        }
        .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    var edgeCount: Int { outgoing.values.reduce(0) { $0 + $1.count } }
}
