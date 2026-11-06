import Foundation
import MLXLMCommon
import SQLite3

/// Research mode: the answer model works in steps with tools — search, read a
/// note, list a folder, list and query the vault's CSV tables — the way Claude
/// Code works in a notes repo: read the domain README, follow its pointers, get
/// numbers from data rather than prose. Everything it reads becomes a numbered
/// source it can cite. Runs on MLX (in-process tool calling); read-only.
enum Agent {
    /// Tool rounds before it must answer.
    static let maxSteps = 8
    /// Characters of a note `read_note` returns (about 2,000 tokens).
    static let readChars = 7000
    /// Rows `query_table` returns.
    static let maxRows = 60

    enum Event: Sendable {
        case step(String)   // "Searching: …", "Reading health/goals.md"
        case token(String)  // streamed text of the current turn
        case resetText      // the streamed text was a preamble to tool calls
    }

    static let instructions = """
    Work in steps with the tools before answering:
    - Start from the folder manuals (README.md in a top-level folder) when a question \
    belongs to one area; they say which file answers which question.
    - Use search to find passages, read_note to read a whole note, list_folder to see \
    what exists (for example every plan in a folder), and list_tables then query_table \
    for numbers kept in CSV files. Prefer data and GENERATED reports for numbers.
    - Every tool result is numbered [n]. Cite those numbers after each claim in the final \
    answer. Do not cite anything you did not get from a tool.
    - Stop calling tools once you can answer; a few calls are usually enough. If the \
    knowledge base does not hold the answer, say so and say where it would belong.
    """

    static var tools: [ToolSpec] {
        func fn(_ name: String, _ desc: String, _ props: [String: [String: String]], _ required: [String]) -> ToolSpec {
            ["type": "function",
             "function": ["name": name, "description": desc,
                          "parameters": ["type": "object", "properties": props, "required": required] as [String: any Sendable]] as [String: any Sendable]]
        }
        return [
            fn("search", "Search the knowledge base by keywords and meaning. Returns the most relevant passages.",
               ["query": ["type": "string", "description": "What to look for"]], ["query"]),
            fn("read_note", "Read a note in full (Markdown), by its vault path such as health/goals.md.",
               ["path": ["type": "string", "description": "Vault-relative path of the note"]], ["path"]),
            fn("list_folder", "List the notes and subfolders in a folder. Use \"\" for the top level.",
               ["path": ["type": "string", "description": "Vault-relative folder path"]], ["path"]),
            fn("list_tables", "List the CSV tables (name, columns, rows) under a folder, for query_table.",
               ["folder": ["type": "string", "description": "Folder to look under, e.g. finance; \"\" for all"]], ["folder"]),
            fn("query_table", "Run one read-only SQLite SELECT over CSV tables named by list_tables. Returns up to 60 rows.",
               ["sql": ["type": "string", "description": "A single SELECT statement"]], ["sql"]),
        ]
    }

    /// Top-level folders with the first line of each README: the map the
    /// model starts from.
    static func vaultOverview() -> String {
        var out = "Top-level folders:\n"
        let fm = FileManager.default
        let dirs = ((try? fm.contentsOfDirectory(atPath: Config.vault.path)) ?? [])
            .filter { !$0.hasPrefix(".") && !$0.hasSuffix("-raw") }
            .filter { var d: ObjCBool = false; return fm.fileExists(atPath: Config.vault.appendingPathComponent($0).path, isDirectory: &d) && d.boolValue }
            .sorted()
        for d in dirs {
            let readme = Config.vault.appendingPathComponent("\(d)/README.md")
            let first = (try? String(contentsOf: readme, encoding: .utf8))?
                .split(separator: "\n").first { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { String($0.prefix(160)) }
            out += "- \(d)/" + (first.map { " — \($0)" } ?? "") + "\n"
        }
        return out
    }

    static func run(_ question: String, embedder: Embedder?, backend: MLXBackend, prior: [(q: String, a: String)] = [],
                    onEvent: @escaping @Sendable (Event) -> Void) async throws -> Answer {
        let t0 = Date()
        let profile = Profile.vaultDefault
        let system = [profile.systemPrompt, instructions, todayLine(), vaultOverview()].joined(separator: "\n\n")
        let params = GenerateParameters(maxTokens: 2000, temperature: Float(Config.temperature), topP: Float(Config.topP),
                                        topK: Config.topK, presencePenalty: Float(Config.presencePenalty))
        // One ChatSession for the whole run keeps the KV cache between steps, so
        // each step only processes the new tool results, not the whole
        // conversation again (that made the first version 12 minutes a question).
        let session = ChatSession(backend.container, instructions: system, generateParameters: params,
                                  additionalContext: Config.templateContext, tools: tools)
        let ctx = ToolContext(embedder: embedder)
        var stats = GenStats(promptTokens: 0, promptSeconds: 0, outputTokens: 0, outputSeconds: 0)
        var final = ""
        // Earlier turns of the conversation come first, so follow-ups make sense.
        var next: [Chat.Message] = prior.suffix(Conversation.turns).flatMap { [Chat.Message.user($0.q), .assistant(String($0.a.prefix(Conversation.answerChars)))] }
        next.append(.user(question))
        for step in 0...maxSteps {
            if step == maxSteps {
                session.tools = nil
                next.append(.user("Answer now from what the tools returned, with [n] citations."))
            }
            var text = ""
            var calls: [ToolCall] = []
            for try await g in session.streamDetails(to: next) {
                switch g {
                case .chunk(let c): text += c; onEvent(.token(c))
                case .toolCall(let c): calls.append(c)
                case .info(let i):
                    stats.promptTokens += i.promptTokenCount; stats.promptSeconds += i.promptTime
                    stats.outputTokens += i.generationTokenCount; stats.outputSeconds += i.generateTime
                default: break
                }
            }
            if calls.isEmpty || step == maxSteps {
                final = text
                break
            }
            onEvent(.resetText)
            next = []
            for call in calls {
                let result = await ctx.call(call) { onEvent(.step($0)) }
                next.append(.tool(result, name: call.function.name))
            }
        }
        final = final.replacingOccurrences(of: #"(?s)<think>.*?</think>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cited = (try? NSRegularExpression(pattern: #"\[(\d+)\]"#))?
            .matches(in: final, range: NSRange(final.startIndex..., in: final))
            .compactMap { Range($0.range(at: 1), in: final).flatMap { Int(final[$0]) } } ?? []
        var bad = Array(Set(cited.filter { $0 < 1 || $0 > ctx.sources.count })).sorted()
        // Answered from folder listings or tables alone: there are no passages to cite, so [n] markers mean nothing.
        if ctx.sources.isEmpty {
            final = final.replacingOccurrences(of: #"\s?\[\d+\]"#, with: "", options: .regularExpression)
            bad = []
        }
        return Answer(text: stripThoughts(final), badCitations: bad, sources: ctx.sources, stats: stats,
                      retrievalSeconds: Date().timeIntervalSince(t0), steps: ctx.log)
    }
}

/// Runs the tools and numbers what they return.
final class ToolContext: @unchecked Sendable {
    let embedder: Embedder?
    var sources: [Chunk] = []
    var log: [String] = []
    private lazy var tables = CSVTables()

    init(embedder: Embedder?) { self.embedder = embedder }

    private func cite(_ c: Chunk) -> Int {
        if let i = sources.firstIndex(where: { $0.relPath == c.relPath && $0.anchor == c.anchor }) { return i + 1 }
        sources.append(c)
        return sources.count
    }

    private func str(_ call: ToolCall, _ key: String) -> String {
        if case .string(let s)? = call.function.arguments[key] { return s }
        return call.function.arguments[key].map { "\($0)" } ?? ""
    }

    func call(_ call: ToolCall, step: (String) -> Void) async -> String {
        let name = call.function.name
        do {
            switch name {
            case "search":
                let q = str(call, "query")
                step("Searched “\(q)”"); log.append("search: \(q)")
                let hits = try await search(q, embedder: embedder, reranker: await Reranker.shared(), limit: 6)
                if hits.isEmpty { return "No relevant passages." }
                return hits.map { h in "[\(cite(h))] \(h.relPath) › \(h.anchor)\n\(h.text.prefix(900))" }.joined(separator: "\n\n")
            case "read_note":
                let p = str(call, "path").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                step("Read \(p)"); log.append("read: \(p)")
                guard let n = findNote(p) ?? Packs.note(p) else { return "No note at \(p). Use list_folder to see what exists." }
                var text = n.body
                if text.count > Agent.readChars { text = String(text.prefix(Agent.readChars)) + "\n[… truncated]" }
                let c = Chunk(noteId: n.id, relPath: n.relPath, title: n.title, anchor: n.title, text: text)
                return "[\(cite(c))] \(n.relPath)\n\(text)"
            case "list_folder":
                let p = str(call, "path").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                step("Listed \(p.isEmpty ? "the vault" : p + "/")"); log.append("list: \(p)")
                return listFolder(p)
            case "list_tables":
                let f = str(call, "folder").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                step("Listed tables\(f.isEmpty ? "" : " in " + f + "/")"); log.append("tables: \(f)")
                return tables.catalog(under: f)
            case "query_table":
                let sql = str(call, "sql")
                step("Queried: \(sql.prefix(80))"); log.append("sql: \(sql)")
                let (out, used) = try tables.query(sql, maxRows: Agent.maxRows)
                let c = Chunk(noteId: used.joined(separator: ","), relPath: used.first ?? "data", title: "Query",
                              anchor: String(sql.prefix(120)), text: "SQL: \(sql)\n\(out)")
                return "[\(cite(c))] Query over \(used.joined(separator: ", "))\n\(out)"
            default:
                return "Unknown tool \(name)."
            }
        } catch {
            return "Error: \(error)"
        }
    }

    func listFolder(_ p: String) -> String {
        let prefix = p.isEmpty ? "" : p + "/"
        var dirs = Set<String>()
        var files: [Note] = []
        for n in allNotes() where n.relPath.hasPrefix(prefix) {
            let rest = n.relPath.dropFirst(prefix.count)
            if let slash = rest.firstIndex(of: "/") { dirs.insert(String(rest[..<slash])) } else { files.append(n) }
        }
        let csvs = tables.files.filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }
        if dirs.isEmpty && files.isEmpty && csvs.isEmpty { return "Nothing at \(p)." }
        var out = ""
        for d in dirs.sorted() { out += "\(prefix)\(d)/\n" }
        for f in files.sorted(by: { $0.relPath < $1.relPath }) { out += "\(f.relPath) — \(f.title)\n" }
        for c in csvs { out += "\(c) (CSV table)\n" }
        return out
    }
}

/// The vault's CSV files as SQLite tables, loaded on first use into an
/// in-memory database (read-only as far as the vault is concerned).
final class CSVTables {
    /// Vault-relative paths of CSV files (git-tracked or not ignored).
    let files: [String]
    private var db: OpaquePointer?
    private var loaded = Set<String>()

    init() {
        // Any in-place vault: a repo, a folder inside one, or a plain folder.
        if Config.inPlace {
            let root = Config.vault.standardizedFileURL.path + "/"
            files = vaultFiles(ext: "csv").map { String($0.standardizedFileURL.path.dropFirst(root.count)) }.sorted()
        } else {
            files = []
        }
        sqlite3_open(":memory:", &db)
    }
    deinit { sqlite3_close(db) }

    static func tableName(_ path: String) -> String {
        String(path.dropLast(4)).lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }.reduce("") { $0 + String($1) }
    }

    private func header(_ path: String) -> (cols: [String], rows: Int) {
        guard let text = try? String(contentsOf: Config.vault.appendingPathComponent(path), encoding: .utf8) else { return ([], 0) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        return (lines.first.map { CSV.parse(String($0)).first ?? [] } ?? [], max(lines.count - 1, 0))
    }

    /// Every note's properties (frontmatter) as one table: path, title, then a column per property.
    static let propsTable = "note_properties"
    private var propsLoaded = false

    private func propertyNotes() -> [Note] { Config.inPlace ? allNotes().filter { !$0.relPath.hasPrefix("@") && !Properties.of($0).isEmpty } : [] }

    private func loadProperties() throws {
        guard !propsLoaded else { return }
        let notes = propertyNotes()
        var keys = Set<String>()
        for n in notes { keys.formUnion(Properties.of(n).keys) }
        let cols = ["path", "title"] + keys.subtracting(["path", "title"]).sorted()
        try exec("CREATE TABLE \(Self.propsTable) (" + cols.map { "\"\($0)\" NUMERIC" }.joined(separator: ", ") + ")")
        var st: OpaquePointer?
        sqlite3_prepare_v2(db, "INSERT INTO \(Self.propsTable) VALUES (" + Array(repeating: "?", count: cols.count).joined(separator: ",") + ")", -1, &st, nil)
        let T = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for n in notes {
            sqlite3_reset(st)
            let p = Properties.of(n)
            for (i, c) in cols.enumerated() {
                let v = c == "path" ? n.relPath : c == "title" ? n.title : p[c]
                if let v, !v.isEmpty { sqlite3_bind_text(st, Int32(i + 1), v, -1, T) } else { sqlite3_bind_null(st, Int32(i + 1)) }
            }
            sqlite3_step(st)
        }
        sqlite3_finalize(st)
        propsLoaded = true
    }

    func catalog(under folder: String) -> String {
        let prefix = folder.isEmpty ? "" : folder + "/"
        let picked = files.filter { $0.hasPrefix(prefix) }
        var props = ""
        if folder.isEmpty {
            let notes = propertyNotes()
            if !notes.isEmpty {
                var keys = Set<String>()
                for n in notes { keys.formUnion(Properties.of(n).keys) }
                props = "\(Self.propsTable) — every note's properties, \(notes.count) rows: path, title, " + keys.sorted().prefix(25).joined(separator: ", ") + "\n"
            }
        }
        if picked.isEmpty { return props.isEmpty ? "No CSV tables under \(folder)." : props }
        return props + picked.prefix(40).map { f in
            let h = header(f)
            return "\(Self.tableName(f)) — \(f), \(h.rows) rows: " + h.cols.prefix(25).joined(separator: ", ")
        }.joined(separator: "\n") + (picked.count > 40 ? "\n(+\(picked.count - 40) more; narrow the folder)" : "")
    }

    private func load(_ path: String) throws {
        guard !loaded.contains(path) else { return }
        let text = try String(contentsOf: Config.vault.appendingPathComponent(path), encoding: .utf8)
        let rows = CSV.parse(text)
        guard let head = rows.first, !head.isEmpty else { throw MacKBError("\(path) is empty") }
        let name = Self.tableName(path)
        let cols = head.enumerated().map { i, c in c.isEmpty ? "col\(i + 1)" : c }
        // NUMERIC affinity: numbers compare and sum as numbers, text stays text.
        let ddl = "CREATE TABLE \"\(name)\" (" + cols.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\" NUMERIC" }.joined(separator: ", ") + ")"
        try exec(ddl)
        try exec("BEGIN")
        var st: OpaquePointer?
        let ins = "INSERT INTO \"\(name)\" VALUES (" + Array(repeating: "?", count: cols.count).joined(separator: ",") + ")"
        sqlite3_prepare_v2(db, ins, -1, &st, nil)
        let T = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for r in rows.dropFirst() {
            sqlite3_reset(st)
            for i in 0..<cols.count {
                if i < r.count, !r[i].isEmpty { sqlite3_bind_text(st, Int32(i + 1), r[i], -1, T) } else { sqlite3_bind_null(st, Int32(i + 1)) }
            }
            sqlite3_step(st)
        }
        sqlite3_finalize(st)
        try exec("COMMIT")
        loaded.insert(path)
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let m = err.map { String(cString: $0) } ?? "?"
            sqlite3_free(err)
            throw MacKBError(m)
        }
    }

    /// Runs one SELECT; loads the tables it names first. Returns a pipe table.
    func query(_ sql: String, maxRows: Int) throws -> (String, [String]) {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("select") || lower.hasPrefix("with"), !trimmed.contains(";") else {
            throw MacKBError("only a single SELECT is allowed")
        }
        let used = files.filter { lower.contains(Self.tableName($0)) }
        let wantsProps = lower.contains(Self.propsTable)
        guard !used.isEmpty || wantsProps else { throw MacKBError("no known table in the query; call list_tables first") }
        if wantsProps { try loadProperties() }
        for f in used { try load(f) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, trimmed, -1, &st, nil) == SQLITE_OK else {
            throw MacKBError(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(st) }
        let n = sqlite3_column_count(st)
        var out = (0..<n).map { String(cString: sqlite3_column_name(st, $0)) }.joined(separator: " | ") + "\n"
        var count = 0
        while sqlite3_step(st) == SQLITE_ROW {
            if count == maxRows { out += "(more rows not shown)\n"; break }
            out += (0..<n).map { i -> String in
                guard let c = sqlite3_column_text(st, i) else { return "" }
                return String(cString: c)
            }.joined(separator: " | ") + "\n"
            count += 1
        }
        if count == 0 { out += "(no rows)\n" }
        return (out, used)
    }
}

/// RFC 4180-ish CSV: quoted fields, doubled quotes, newlines inside quotes.
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var it = text.makeIterator()
        var pending: Character?
        while let ch = pending ?? it.next() {
            pending = nil
            if quoted {
                if ch == "\"" {
                    if let nx = it.next() {
                        if nx == "\"" { field.append("\"") } else { quoted = false; pending = nx }
                    } else { quoted = false }
                } else { field.append(ch) }
                continue
            }
            switch ch {
            case "\"": quoted = true
            case ",": row.append(field); field = ""
            case "\n", "\r\n": row.append(field); field = ""; rows.append(row); row = []
            case "\r": break
            default: field.append(ch)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
