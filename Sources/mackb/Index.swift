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
}

/// Split a note into ~chunkChars passages, each starting on a timestamp or
/// under a heading, so every citation lands somewhere meaningful.
func chunkNote(_ note: Note, chunkChars: Int = 1200) -> [Chunk] {
    var chunks: [Chunk] = []
    var heading = note.title
    var anchor = note.title
    var buf = ""
    let tsBracket = try! NSRegularExpression(pattern: #"^\[(\d\d:\d\d:\d\d)\]"#)
    let tsBold = try! NSRegularExpression(pattern: #"^\*\*(\d\d:\d\d:\d\d)\*\*"#)
    func flush() {
        let t = buf.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count > 30 {
            let header = note.title == heading ? note.title : "\(note.title) — \(heading)"
            chunks.append(Chunk(noteId: note.id, relPath: note.relPath, title: note.title, anchor: anchor,
                                text: header + "\n" + t))
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

    init(path: URL = Config.indexPath) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(path.path, &db) == SQLITE_OK else { throw MacKBError("can't open index") }
        try exec("""
            CREATE TABLE IF NOT EXISTS chunks(id INTEGER PRIMARY KEY, note_id TEXT, rel_path TEXT, title TEXT,
                anchor TEXT, text TEXT, mtime REAL, vec BLOB);
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(text, title, content='chunks', content_rowid='id',
                tokenize='porter unicode61');
            CREATE INDEX IF NOT EXISTS chunks_note ON chunks(rel_path);
            """)
    }
    deinit { sqlite3_close(db) }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let m = err.map { String(cString: $0) } ?? "?"
            sqlite3_free(err)
            throw MacKBError("sqlite: \(m)")
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
            throw MacKBError("sqlite: \(String(cString: sqlite3_errmsg(db)))")
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
        let st = try prepare("INSERT INTO chunks(note_id, rel_path, title, anchor, text, mtime, vec) VALUES(?,?,?,?,?,?,?)")
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
        guard sqlite3_step(st) == SQLITE_DONE else { throw MacKBError("insert failed") }
        let id = sqlite3_last_insert_rowid(db)
        let f = try prepare("INSERT INTO chunks_fts(rowid, text, title) VALUES(?, ?, ?)")
        sqlite3_bind_int64(f, 1, id)
        sqlite3_bind_text(f, 2, c.text, -1, TRANSIENT)
        sqlite3_bind_text(f, 3, c.title, -1, TRANSIENT)
        sqlite3_step(f)
        sqlite3_finalize(f)
    }

    private func chunk(from st: OpaquePointer?) -> (Int64, Chunk) {
        (sqlite3_column_int64(st, 0),
         Chunk(noteId: String(cString: sqlite3_column_text(st, 1)), relPath: String(cString: sqlite3_column_text(st, 2)),
               title: String(cString: sqlite3_column_text(st, 3)), anchor: String(cString: sqlite3_column_text(st, 4)),
               text: String(cString: sqlite3_column_text(st, 5))))
    }

    /// BM25 keyword search. Words are OR'd so a natural-language question still matches.
    func keyword(_ q: String, limit: Int) throws -> [(Int64, Chunk)] {
        let words = q.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopwords.contains($0) }
        guard !words.isEmpty else { return [] }
        let match = words.map { "\"\($0)\"" }.joined(separator: " OR ")
        let st = try prepare("""
            SELECT c.id, c.note_id, c.rel_path, c.title, c.anchor, c.text FROM chunks_fts f JOIN chunks c ON c.id = f.rowid
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
        let st = try prepare("SELECT id, note_id, rel_path, title, anchor, text, vec FROM chunks WHERE vec IS NOT NULL")
        defer { sqlite3_finalize(st) }
        var scored: [(Float, Int64, Chunk)] = []
        while sqlite3_step(st) == SQLITE_ROW {
            let n = Int(sqlite3_column_bytes(st, 6)) / 4
            guard n == q.count, let p = sqlite3_column_blob(st, 6) else { continue }
            let v = p.assumingMemoryBound(to: Float.self)
            var dot: Float = 0
            for i in 0..<n { dot += v[i] * q[i] }  // vectors are L2-normalised
            let (id, c) = chunk(from: st)
            scored.append((dot, id, c))
        }
        return scored.sorted { $0.0 > $1.0 }.prefix(limit).map { ($0.1, $0.2) }
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
    let idx = try Index()
    if force { try idx.exec("DELETE FROM chunks; INSERT INTO chunks_fts(chunks_fts) VALUES('rebuild');") }
    let have = try idx.indexedMtimes()
    let notes = allNotes()
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

/// Hybrid retrieval: keyword + vector lists merged by reciprocal rank fusion.
func search(_ q: String, embedder: Embedder?, limit: Int) async throws -> [Chunk] {
    let idx = try Index()
    let kw = try idx.keyword(q, limit: 40)
    var vec: [(Int64, Chunk)] = []
    if let embedder, let qv = try await embedder.embed([q], query: true).first {
        vec = try idx.vector(qv, limit: 40)
    }
    var score: [Int64: Double] = [:]
    var byId: [Int64: Chunk] = [:]
    for list in [kw, vec] {
        for (rank, (id, c)) in list.enumerated() {
            score[id, default: 0] += 1.0 / (Config.rrfK + Double(rank + 1))
            byId[id] = c
        }
    }
    return score.sorted { $0.value > $1.value }.prefix(limit).map { byId[$0.key]! }
}
