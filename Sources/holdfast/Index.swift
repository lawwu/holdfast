import Foundation
import SQLite3

/// A retrievable passage. `anchor` is what a citation points at: a timestamp
/// (hh:mm:ss) for recordings, otherwise the nearest heading.
struct Chunk {
    var noteId: String
    var relPath: String
    var title: String
    var anchor: String
    var text: String
    /// Position within its note, so neighbouring passages can be merged.
    var ord: Int = 0
    /// Case-report metadata from frontmatter, for filters and spread retrieval.
    var session: Int? = nil
    var caseId: String? = nil
    /// Reranker relevance (0…1) once scored.
    var score: Double? = nil
}

/// Split a note into ~chunkChars passages, each starting on a timestamp or
/// under a heading, so every citation lands somewhere meaningful.
///
/// Every passage starts with a context line built from metadata, no LLM:
/// "Case Report — D.M. — Session 4 › 2026-08-27 › What homework was given…".
/// It is indexed for both keyword and vector search (contextual retrieval; see
/// oss-best-practices.md #3), so a passage still says which session it is from.
func chunkNote(_ note: Note, chunkChars: Int = 1200) -> [Chunk] {
    var chunks: [Chunk] = []
    var heading = note.title
    var anchor = note.title
    var buf = ""
    let tsBracket = try! NSRegularExpression(pattern: #"^\[(\d\d:\d\d:\d\d)\]"#)
    let tsBold = try! NSRegularExpression(pattern: #"^\*\*(\d\d:\d\d:\d\d)\*\*"#)
    let session = note.meta["session"].flatMap { Int($0) }
    func flush() {
        let t = buf.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count > 30 {
            var crumbs = [note.title]
            if let d = note.meta["date"], !note.title.contains(d) { crumbs.append(d) }
            if let k = note.meta["session_kind"] { crumbs.append(k) }
            if heading != note.title { crumbs.append(heading) }
            chunks.append(Chunk(noteId: note.id, relPath: note.relPath, title: note.title, anchor: anchor,
                                text: crumbs.joined(separator: " › ") + "\n" + t,
                                ord: chunks.count, session: session, caseId: note.meta["case"]))
        }
        buf = ""
    }
    for raw in note.body.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(raw)
        if line.hasPrefix("#") {
            flush()
            heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            anchor = heading
            continue
        }
        let r = NSRange(line.startIndex..., in: line)
        let ts = (tsBracket.firstMatch(in: line, range: r) ?? tsBold.firstMatch(in: line, range: r))
            .flatMap { Range($0.range(at: 1), in: line).map { String(line[$0]) } }
        if let ts, buf.isEmpty { anchor = ts }
        if buf.count + line.count > chunkChars, !buf.isEmpty {
            flush()
            if let ts { anchor = ts }  // next chunk starts at this timestamp
        }
        buf += line + "\n"
    }
    flush()
    return chunks
}

final class Index {
    private var db: OpaquePointer?
    /// Bump when the schema or chunking changes: the index is a cache and rebuilds.
    static let schemaVersion: Int32 = 3

    init(path: URL = Config.indexPath) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(path.path, &db) == SQLITE_OK else { throw HoldfastError("can't open index") }
        if userVersion() != Self.schemaVersion {
            try exec("DROP TABLE IF EXISTS chunks_fts; DROP TABLE IF EXISTS chunks;")
            try exec("PRAGMA user_version = \(Self.schemaVersion)")
        }
        try exec("""
            CREATE TABLE IF NOT EXISTS chunks(id INTEGER PRIMARY KEY, note_id TEXT, rel_path TEXT, title TEXT,
                anchor TEXT, text TEXT, mtime REAL, vec BLOB, ord INTEGER, session INTEGER, case_id TEXT);
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(text, title, content='chunks', content_rowid='id',
                tokenize='porter unicode61');
            CREATE INDEX IF NOT EXISTS chunks_note ON chunks(rel_path);
            """)
    }
    deinit { sqlite3_close(db) }

    private func userVersion() -> Int32 {
        guard let st = try? prepare("PRAGMA user_version") else { return 0 }
        defer { sqlite3_finalize(st) }
        return sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_int(st, 0) : 0
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let m = err.map { String(cString: $0) } ?? "?"
            sqlite3_free(err)
            throw HoldfastError("sqlite: \(m)")
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
            throw HoldfastError("sqlite: \(String(cString: sqlite3_errmsg(db)))")
        }
        return st
    }

    private let TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Which notes changed since last index (by mtime); returns (path → mtime).
    func indexedMtimes() throws -> [String: Double] {
        let st = try prepare("SELECT rel_path, MAX(mtime) FROM chunks GROUP BY rel_path")
        defer { sqlite3_finalize(st) }
        var out: [String: Double] = [:]
        while sqlite3_step(st) == SQLITE_ROW {
            out[String(cString: sqlite3_column_text(st, 0))] = sqlite3_column_double(st, 1)
        }
        return out
    }

    func deleteNote(_ relPath: String) throws {
        // External-content FTS: remove rows from the index before deleting the content.
        let sel = try prepare("SELECT id, text, title FROM chunks WHERE rel_path = ?")
        sqlite3_bind_text(sel, 1, relPath, -1, TRANSIENT)
        var rows: [(Int64, String, String)] = []
        while sqlite3_step(sel) == SQLITE_ROW {
            rows.append((sqlite3_column_int64(sel, 0), String(cString: sqlite3_column_text(sel, 1)), String(cString: sqlite3_column_text(sel, 2))))
        }
        sqlite3_finalize(sel)
        for (id, text, title) in rows {
            let d = try prepare("INSERT INTO chunks_fts(chunks_fts, rowid, text, title) VALUES('delete', ?, ?, ?)")
            sqlite3_bind_int64(d, 1, id)
            sqlite3_bind_text(d, 2, text, -1, TRANSIENT)
            sqlite3_bind_text(d, 3, title, -1, TRANSIENT)
            sqlite3_step(d)
            sqlite3_finalize(d)
        }
        let del = try prepare("DELETE FROM chunks WHERE rel_path = ?")
        sqlite3_bind_text(del, 1, relPath, -1, TRANSIENT)
        sqlite3_step(del)
        sqlite3_finalize(del)
    }

    func insert(_ c: Chunk, mtime: Double, vec: [Float]?) throws {
        let st = try prepare("""
            INSERT INTO chunks(note_id, rel_path, title, anchor, text, mtime, vec, ord, session, case_id)
            VALUES(?,?,?,?,?,?,?,?,?,?)
            """)
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, c.noteId, -1, TRANSIENT)
        sqlite3_bind_text(st, 2, c.relPath, -1, TRANSIENT)
        sqlite3_bind_text(st, 3, c.title, -1, TRANSIENT)
        sqlite3_bind_text(st, 4, c.anchor, -1, TRANSIENT)
        sqlite3_bind_text(st, 5, c.text, -1, TRANSIENT)
        sqlite3_bind_double(st, 6, mtime)
        if let vec {
            vec.withUnsafeBytes { sqlite3_bind_blob(st, 7, $0.baseAddress, Int32($0.count), TRANSIENT) }
        } else {
            sqlite3_bind_null(st, 7)
        }
        sqlite3_bind_int(st, 8, Int32(c.ord))
        if let s = c.session { sqlite3_bind_int(st, 9, Int32(s)) } else { sqlite3_bind_null(st, 9) }
        if let k = c.caseId { sqlite3_bind_text(st, 10, k, -1, TRANSIENT) } else { sqlite3_bind_null(st, 10) }
        guard sqlite3_step(st) == SQLITE_DONE else { throw HoldfastError("insert failed") }
        let id = sqlite3_last_insert_rowid(db)
        let f = try prepare("INSERT INTO chunks_fts(rowid, text, title) VALUES(?, ?, ?)")
        sqlite3_bind_int64(f, 1, id)
        sqlite3_bind_text(f, 2, c.text, -1, TRANSIENT)
        sqlite3_bind_text(f, 3, c.title, -1, TRANSIENT)
        sqlite3_step(f)
        sqlite3_finalize(f)
    }

    private static let cols = "c.id, c.note_id, c.rel_path, c.title, c.anchor, c.text, c.ord, c.session, c.case_id"

    private func chunk(from st: OpaquePointer?) -> (Int64, Chunk) {
        (sqlite3_column_int64(st, 0),
         Chunk(noteId: String(cString: sqlite3_column_text(st, 1)), relPath: String(cString: sqlite3_column_text(st, 2)),
               title: String(cString: sqlite3_column_text(st, 3)), anchor: String(cString: sqlite3_column_text(st, 4)),
               text: String(cString: sqlite3_column_text(st, 5)), ord: Int(sqlite3_column_int(st, 6)),
               session: sqlite3_column_type(st, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int(st, 7)),
               caseId: sqlite3_column_type(st, 8) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(st, 8))))
    }

    /// BM25 keyword search. Words are OR'd so a natural-language question still matches.
    func keyword(_ q: String, limit: Int) throws -> [(Int64, Chunk)] {
        let words = q.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopwords.contains($0) }
        guard !words.isEmpty else { return [] }
        let match = words.map { "\"\($0)\"" }.joined(separator: " OR ")
        let st = try prepare("""
            SELECT \(Self.cols) FROM chunks_fts f JOIN chunks c ON c.id = f.rowid
            WHERE chunks_fts MATCH ? ORDER BY bm25(chunks_fts, 1.0, 2.0) LIMIT ?
            """)
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, match, -1, TRANSIENT)
        sqlite3_bind_int(st, 2, Int32(limit))
        var out: [(Int64, Chunk)] = []
        while sqlite3_step(st) == SQLITE_ROW { out.append(chunk(from: st)) }
        return out
    }

    /// Brute-force cosine over all vectors. Fine to ~100k chunks on a Mac; sqlite-vec later.
    func vector(_ q: [Float], limit: Int) throws -> [(Int64, Chunk)] {
        let st = try prepare("SELECT \(Self.cols), c.vec FROM chunks c WHERE c.vec IS NOT NULL")
        defer { sqlite3_finalize(st) }
        var scored: [(Float, Int64, Chunk)] = []
        while sqlite3_step(st) == SQLITE_ROW {
            let n = Int(sqlite3_column_bytes(st, 9)) / 4
            guard n == q.count, let p = sqlite3_column_blob(st, 9) else { continue }
            let v = p.assumingMemoryBound(to: Float.self)
            var dot: Float = 0
            for i in 0..<n { dot += v[i] * q[i] }  // vectors are L2-normalised
            let (id, c) = chunk(from: st)
            scored.append((dot, id, c))
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(limit).map { ($0.1, $0.2) }
    }

    /// Cosine scores too (for Related notes, which shows how close each one is).
    func vectorScored(_ q: [Float], limit: Int) throws -> [(Float, Chunk)] {
        let st = try prepare("SELECT \(Self.cols), c.vec FROM chunks c WHERE c.vec IS NOT NULL")
        defer { sqlite3_finalize(st) }
        var scored: [(Float, Chunk)] = []
        while sqlite3_step(st) == SQLITE_ROW {
            let n = Int(sqlite3_column_bytes(st, 9)) / 4
            guard n == q.count, let p = sqlite3_column_blob(st, 9) else { continue }
            let v = p.assumingMemoryBound(to: Float.self)
            var dot: Float = 0
            for i in 0..<n { dot += v[i] * q[i] }
            scored.append((dot, chunk(from: st).1))
        }
        return Array(scored.sorted { $0.0 > $1.0 }.prefix(limit))
    }

    /// The embedding of each passage of one note.
    func vectors(of relPath: String) throws -> [[Float]] {
        let st = try prepare("SELECT vec FROM chunks WHERE rel_path = ? AND vec IS NOT NULL ORDER BY ord")
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, relPath, -1, TRANSIENT)
        var out: [[Float]] = []
        while sqlite3_step(st) == SQLITE_ROW {
            let n = Int(sqlite3_column_bytes(st, 0)) / 4
            guard n > 0, let p = sqlite3_column_blob(st, 0) else { continue }
            out.append(Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: Float.self), count: n)))
        }
        return out
    }

    /// All passages of the given sessions (used when a question names a session).
    func bySessions(_ sessions: Set<Int>) throws -> [(Int64, Chunk)] {
        guard !sessions.isEmpty else { return [] }
        let st = try prepare("SELECT \(Self.cols) FROM chunks c WHERE c.session IN (\(sessions.map(String.init).joined(separator: ",")))")
        defer { sqlite3_finalize(st) }
        var out: [(Int64, Chunk)] = []
        while sqlite3_step(st) == SQLITE_ROW { out.append(chunk(from: st)) }
        return out
    }

    /// Specific passages of one note by position (for neighbour expansion).
    func byOrds(_ relPath: String, _ ords: [Int]) throws -> [Chunk] {
        guard !ords.isEmpty else { return [] }
        let st = try prepare("SELECT \(Self.cols) FROM chunks c WHERE c.rel_path = ? AND c.ord IN (\(ords.map(String.init).joined(separator: ",")))")
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, relPath, -1, TRANSIENT)
        var out: [Chunk] = []
        while sqlite3_step(st) == SQLITE_ROW { out.append(chunk(from: st).1) }
        return out
    }

    /// Sessions whose label mentions `kind` (e.g. "joint"), in order.
    func sessions(ofKind kind: String) -> [Int] {
        guard let st = try? prepare("SELECT DISTINCT session FROM chunks WHERE session IS NOT NULL AND text LIKE ? ORDER BY session") else { return [] }
        defer { sqlite3_finalize(st) }
        sqlite3_bind_text(st, 1, "% › \(kind) session%", -1, TRANSIENT)  // the label, not the body
        var out: [Int] = []
        while sqlite3_step(st) == SQLITE_ROW { out.append(Int(sqlite3_column_int(st, 0))) }
        return out
    }

    func maxSession() -> Int? {
        guard let st = try? prepare("SELECT MAX(session) FROM chunks") else { return nil }
        defer { sqlite3_finalize(st) }
        guard sqlite3_step(st) == SQLITE_ROW, sqlite3_column_type(st, 0) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(st, 0))
    }

    func count() -> (chunks: Int, notes: Int, vectors: Int) {
        guard let st = try? prepare("SELECT COUNT(*), COUNT(DISTINCT rel_path), COUNT(vec) FROM chunks") else { return (0, 0, 0) }
        defer { sqlite3_finalize(st) }
        sqlite3_step(st)
        return (Int(sqlite3_column_int(st, 0)), Int(sqlite3_column_int(st, 1)), Int(sqlite3_column_int(st, 2)))
    }
}

let stopwords: Set<String> = ["the", "and", "for", "are", "was", "what", "how", "did", "does", "with", "that", "this",
    "from", "have", "has", "had", "you", "your", "about", "which", "when", "who", "why", "where", "can", "any", "all",
    "our", "his", "her", "they", "them", "their", "there", "were", "been", "into", "would", "should", "could", "tell"]

/// Re-index changed notes. Embeddings are optional: keyword search still works without them.
func reindex(embedder: Embedder?, force: Bool = false) async throws {
    try await reindexNotes(Index(), notes: allNotes(), embedder: embedder, force: force)
}

/// Brings one index up to date with a set of notes (the vault's, or a knowledge pack's).
func reindexNotes(_ idx: Index, notes: [Note], embedder: Embedder?, force: Bool = false) async throws {
    if force { try idx.exec("DELETE FROM chunks; INSERT INTO chunks_fts(chunks_fts) VALUES('rebuild');") }
    let have = try idx.indexedMtimes()
    let live = Set(notes.map { $0.relPath })
    for gone in have.keys where !live.contains(gone) { try idx.deleteNote(gone) }
    var todo: [(Note, Double)] = []
    for n in notes {
        let m = (try? FileManager.default.attributesOfItem(atPath: n.path.path)[.modificationDate] as? Date)??.timeIntervalSince1970 ?? 0
        if let h = have[n.relPath], h >= m { continue }
        todo.append((n, m))
    }
    log("indexing \(todo.count) changed notes (\(notes.count) in vault)…")
    let t0 = Date()
    var nChunks = 0
    try idx.exec("BEGIN")
    for (i, (n, m)) in todo.enumerated() {
        try idx.deleteNote(n.relPath)
        let chunks = chunkNote(n)
        let vecs = try await embedder?.embed(chunks.map { $0.text }, query: false)
        for (j, c) in chunks.enumerated() { try idx.insert(c, mtime: m, vec: vecs?[j]) }
        nChunks += chunks.count
        if (i + 1) % 25 == 0 { log("  \(i + 1)/\(todo.count) notes, \(nChunks) chunks") }
    }
    try idx.exec("COMMIT")
    let c = idx.count()
    log(String(format: "indexed %d chunks in %.1fs; index now %d notes, %d chunks, %d with vectors",
               nChunks, Date().timeIntervalSince(t0), c.notes, c.chunks, c.vectors))
}

// MARK: - Query understanding

struct QueryPlan {
    /// Sessions the question names ("first session", "session 4", "final session").
    var sessions: Set<Int> = []
    /// The question spans the case ("across sessions", "over the course of").
    var spread = false
}

func planQuery(_ q: String, maxSession: Int?, sessionsOfKind: (String) -> [Int] = { _ in [] }) -> QueryPlan {
    var plan = QueryPlan()
    let lower = q.lowercased()
    let ordinals = ["first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7,
                    "eighth": 8, "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12]
    for (w, n) in ordinals where lower.range(of: "\\b\(w) (session|meeting|counseling session)", options: .regularExpression) != nil {
        plan.sessions.insert(n)
    }
    // "the second joint session": the nth session whose form header says "joint".
    if let re = try? NSRegularExpression(pattern: #"\b(first|second|third|fourth|fifth|last|final) ([a-z]+) (session|meeting)\b"#) {
        for m in re.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
            guard let o = Range(m.range(at: 1), in: lower), let k = Range(m.range(at: 2), in: lower) else { continue }
            let kind = String(lower[k])
            if ["counseling", "next", "previous", "this", "that"].contains(kind) { continue }
            let list = sessionsOfKind(kind)
            guard !list.isEmpty else { continue }
            let word = String(lower[o])
            let idx = (word == "last" || word == "final") ? list.count - 1 : (ordinals[word] ?? 0) - 1
            if idx >= 0, idx < list.count { plan.sessions.insert(list[idx]) }
        }
    }
    // In biblical counseling, "graduation" is the final session.
    if let mx = maxSession, lower.range(of: #"\bgraduat"#, options: .regularExpression) != nil, plan.sessions.isEmpty {
        plan.sessions.insert(mx)
    }
    if let re = try? NSRegularExpression(pattern: #"\bsession\s*#?\s*(\d{1,3})\b|\b(\d{1,3})(?:st|nd|rd|th) session\b"#) {
        for m in re.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)) {
            for g in 1...2 { if let r = Range(m.range(at: g), in: lower), let n = Int(lower[r]) { plan.sessions.insert(n) } }
        }
    }
    if let mx = maxSession, lower.range(of: #"\b(last|final|graduation) session\b"#, options: .regularExpression) != nil {
        plan.sessions.insert(mx)
    }
    let spreadCues = ["across", "over the course", "throughout", "all sessions", "every session", "each session",
                      "which sessions", "in which session", "from the start", "start to the end", "beginning to the end",
                      "over time", "change from", "changed from", "over the sessions", "how has", "how have"]
    // Spread selection groups by session, so it only makes sense with case reports.
    plan.spread = maxSession != nil && plan.sessions.isEmpty && spreadCues.contains { lower.contains($0) }
    return plan
}

// MARK: - Retrieval

/// Retrieval tuning (see oss-best-practices.md #1, #2, #5, #7).
enum Retrieval {
    /// Candidates from keyword + vector search, before reranking.
    static let candidates = 60
    /// Passages sent to the LLM.
    static let finalPassages = 8
    /// At most this many passages from one note (stops one note crowding the context).
    static let perNote = 2
    /// In spread mode, passages per session.
    static let perSession = 2
    /// Below this best reranker score the materials don't cover the question:
    /// abstain without calling the LLM. Qwen3-Reranker scores are 0…1.
    static let abstainBelow = 0.08
    /// How much a knowledge pack's ranking counts against the vault's when there is no reranker.
    static let packWeightWithoutReranker = 0.35
    /// Drop candidates scoring below this share of the best one.
    static let relativeFloor = 0.5
    /// Passages sent for a question that spans the case.
    static let spreadPassages = 12
    /// Add the neighbours of this many top passages.
    static let expandTop = 2
    /// A note "dominates" when it has this many of the top `dominanceWindow` hits…
    static let dominanceHits = 3
    static let dominanceWindow = 5
    /// …and then gets this many passages, down to this share of the best score.
    static let dominantBudget = 5
    static let dominantFloor = 0.3
}

/// Hybrid retrieval: keyword + vector lists merged by reciprocal rank fusion,
/// then (if a reranker is loaded) cross-encoder reranking, per-note caps,
/// neighbour merging, and session-aware selection.
func search(_ q: String, embedder: Embedder?, reranker: Reranker? = nil, limit: Int, packs: Bool = true) async throws -> [Chunk] {
    let idx = try Index()
    let plan = planQuery(q, maxSession: idx.maxSession(), sessionsOfKind: { idx.sessions(ofKind: $0) })
    // The vault's index, then each knowledge pack that is switched on: each is ranked
    // on its own (keyword + vector, fused), then the lists are merged by that rank.
    var sources: [(key: String, idx: Index)] = [("vault", idx)]
    if packs { for id in Packs.searchable() where Packs.validID(id) { if let p = try? Index(path: Packs.indexPath(id)) { sources.append(("pack:" + id, p)) } } }
    let qv: [Float]? = embedder == nil ? nil : try await embedder!.embed([q], query: true).first
    var score: [String: Double] = [:]
    var byId: [String: Chunk] = [:]
    for (key, sidx) in sources {
        let kw = try sidx.keyword(q, limit: Retrieval.candidates)
        let vec = qv.map { try? sidx.vector($0, limit: Retrieval.candidates) } ?? nil
        // Without a reranker to judge them, a pack's best passages shouldn't tie your notes' best:
        // pack ranks count for less (the reranker sorts it out when it is there).
        let weight = key == "vault" || reranker != nil ? 1.0 : Retrieval.packWeightWithoutReranker
        for list in [kw, vec ?? []] {
            for (rank, (id, c)) in list.enumerated() {
                let k = "\(key)#\(id)"
                score[k, default: 0] += weight / (Config.rrfK + Double(rank + 1))
                byId[k] = c
            }
        }
    }
    func index(for c: Chunk) -> Index { Packs.id(of: c.relPath).flatMap { id in sources.first { $0.key == "pack:" + id }?.idx } ?? idx }
    // A named session: everything from that session is a candidate, and nothing else.
    if !plan.sessions.isEmpty {
        let pinned = try idx.bySessions(plan.sessions)
        if !pinned.isEmpty {
            for (id, c) in pinned where byId["vault#\(id)"] == nil { byId["vault#\(id)"] = c; score["vault#\(id)"] = 0 }
            byId = byId.filter { plan.sessions.contains($0.value.session ?? -1) }
        }
    }
    var cands = byId.keys.sorted { score[$0, default: 0] > score[$1, default: 0] }.prefix(Retrieval.candidates).map { byId[$0]! }

    guard let reranker else {
        return Array(capPerNote(cands, Retrieval.perNote).prefix(limit))
    }
    let scores = try await reranker.score(query: q, documents: cands.map { $0.text })
    for i in cands.indices { cands[i].score = scores[i] }
    cands.sort { ($0.score ?? 0) > ($1.score ?? 0) }
    if ProcessInfo.processInfo.environment["HOLDFAST_DEBUG"] != nil {
        for c in cands.prefix(20) { log(String(format: "  %.3f  %@ #%d %@", c.score ?? 0, c.noteId, c.ord, String(c.anchor.prefix(50)))) }
    }
    if (cands.first?.score ?? 0) < Retrieval.abstainBelow {
        log(String(format: "best reranker score %.3f < %.2f: abstaining", cands.first?.score ?? 0, Retrieval.abstainBelow))
        return []
    }

    // Keep passages that are relevant in their own right, not just the least bad.
    // One exception: when a single note holds most of the top hits, the question is
    // about that note, and its other sections (in other words: "setback" for
    // "relapse") get a lower floor and a bigger budget.
    let best = cands.first?.score ?? 0
    let floor = max(Retrieval.abstainBelow, best * Retrieval.relativeFloor)
    let top = cands.prefix(Retrieval.dominanceWindow)
    let dominant = Dictionary(grouping: top, by: \.relPath)
        .first { $0.value.count >= Retrieval.dominanceHits }?.key
    let domFloor = max(Retrieval.abstainBelow, best * Retrieval.dominantFloor)
    cands = cands.filter { c in
        (c.score ?? 0) >= (c.relPath == dominant ? domFloor : floor)
    }

    var picked: [Chunk]
    if plan.spread {
        // Best one or two passages from each session, chosen by score, sent in session order.
        var perSession: [Int: Int] = [:]
        var chosen: [Chunk] = []
        for c in cands {
            let s = c.session ?? -1
            if perSession[s, default: 0] < Retrieval.perSession {
                perSession[s, default: 0] += 1
                chosen.append(c)
            }
            if chosen.count >= Retrieval.spreadPassages { break }
        }
        picked = chosen.sorted { ($0.session ?? 999, $0.ord) < ($1.session ?? 999, $1.ord) }
    } else {
        // A named session may need more of that one note; otherwise cap each note.
        let cap = plan.sessions.isEmpty ? Retrieval.perNote : Retrieval.finalPassages
        var n: [String: Int] = [:]
        picked = Array(cands.filter { c in
            n[c.relPath, default: 0] += 1
            return n[c.relPath]! <= (c.relPath == dominant ? max(cap, Retrieval.dominantBudget) : cap)
        }.prefix(limit))
        // Neighbour expansion (sentence-window retrieval): the passages around the top
        // hits often hold the event itself, in words the question doesn't use
        // ("setback" for "relapse"). Merged into the hit, so the passage count stays.
        for c in picked.prefix(Retrieval.expandTop) {
            let have = Set(picked.filter { $0.relPath == c.relPath }.map(\.ord))
            let extra = try index(for: c).byOrds(c.relPath, [c.ord - 1, c.ord + 1].filter { $0 >= 0 && !have.contains($0) })
            picked += extra.map { var e = $0; e.score = c.score; return e }
        }
    }
    return mergeNeighbours(picked)
}

func capPerNote(_ cs: [Chunk], _ cap: Int) -> [Chunk] {
    var n: [String: Int] = [:]
    return cs.filter { c in
        n[c.relPath, default: 0] += 1
        return n[c.relPath]! <= cap
    }
}

/// Passages from the same note that sit next to each other become one passage,
/// keeping the first one's position and anchor (AutoMerging, oss-best-practices.md #2).
func mergeNeighbours(_ cs: [Chunk]) -> [Chunk] {
    var out: [Chunk] = []
    var span: [(lo: Int, hi: Int)] = []  // ord range each merged passage covers
    for c in cs {
        if let i = out.indices.first(where: { out[$0].relPath == c.relPath && (c.ord == span[$0].hi + 1 || c.ord == span[$0].lo - 1) }) {
            var m = out[i]
            let body = c.text.split(separator: "\n", maxSplits: 1).last.map(String.init) ?? c.text
            let header = c.text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
            let section = header.components(separatedBy: " › ").last ?? ""
            if c.ord > span[i].hi {
                m.text += "\n\n" + (section.isEmpty ? "" : "## \(section)\n") + body
            } else {
                let mBody = m.text.split(separator: "\n", maxSplits: 1).last.map(String.init) ?? m.text
                let mSection = (m.text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "").components(separatedBy: " › ").last ?? ""
                m.text = header + "\n" + body + "\n\n## \(mSection)\n" + mBody
                m.anchor = c.anchor
                m.ord = c.ord
            }
            m.score = max(m.score ?? 0, c.score ?? 0)
            out[i] = m
            span[i] = (min(span[i].lo, c.ord), max(span[i].hi, c.ord))
        } else {
            out.append(c)
            span.append((c.ord, c.ord))
        }
    }
    return out
}
