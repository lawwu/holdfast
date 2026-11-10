import Foundation
import SQLite3

/// Research mode: the answer model works in steps with tools — search, read a
/// note, list a folder, list and query the vault's CSV tables — the way Claude
/// Code works in a notes repo: read the domain README, follow its pointers, get
/// numbers from data rather than prose. Everything it reads becomes a numbered
/// source it can cite. Changes are proposals; only the Inbox can apply them.
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
        case stepDetail(String)  // the exact call and what it returned, for the step just announced
        case sources([Chunk])    // passages gathered so far, so [n] links work before the answer is done
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
    - When the user asks you to change a note (tick an item done, add a row or a line, correct \
    a fact), read_note it first, then call propose_edit with the exact text to replace, copied \
    from the note, and the new text. The change waits in the Inbox for the user to approve; \
    say so in your answer. Change only what was asked.
    """

    static var tools: [AgentRuntime.ToolSpec] {
        func fn(_ name: String, _ desc: String, _ props: [String: [String: String]], _ required: [String]) -> AgentRuntime.ToolSpec {
            AgentRuntime.ToolSpec(name: name, description: desc,
                                  fields: props.mapValues { $0["description"] ?? "" }, required: required)
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
            fn("propose_edit", "Propose a change to a note, for the user to approve in the Inbox. Replaces old_text (copied exactly from the note, matching once) with new_text; an empty old_text adds new_text at the end of the note.",
               ["path": ["type": "string", "description": "Vault-relative path of the note, e.g. finance/open-items.md"],
                "old_text": ["type": "string", "description": "The exact text to replace, e.g. a whole checklist line; \"\" to add at the end"],
                "new_text": ["type": "string", "description": "The text to put in its place"],
                "why": ["type": "string", "description": "One short line saying what the change does"]], ["path", "old_text", "new_text"]),
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
            if Profile.isPrivate(d) {
                out += "- \(d)/ — local-only notes\n"
                continue
            }
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
        try await run(question, embedder: embedder, model: MLXAgentModel(backend: backend), prior: prior, onEvent: onEvent)
    }

    /// Both adapters enter the same runtime. Tool policy and Inbox writes belong to Holdfast.
    static func run(_ question: String, embedder: Embedder?, model: any AgentRuntime.Model,
                    prior: [(q: String, a: String)] = [], onEvent: @escaping @Sendable (Event) -> Void) async throws -> Answer {
        let t0 = Date()
        let system = [Profile.vaultDefault.systemPrompt, instructions, todayLine(), vaultOverview()].joined(separator: "\n\n")
        let ctx = ToolContext(embedder: embedder)
        let registry = tools.map { spec in
            AgentRuntime.Tool(spec: spec) { args in
                let result = await ctx.call(spec.name, args: args)
                return AgentRuntime.ToolResult(text: result, isError: result.hasPrefix("Error:"),
                                               localOnly: ctx.touchedPrivateNotes)
            }
        }
        let history: [AgentRuntime.Message] = prior.suffix(Conversation.turns).flatMap {
            [.user($0.q), .assistant(.init(text: String($0.a.prefix(Conversation.answerChars))))]
        }
        var policy = AgentRuntime.Policy(maxToolRounds: maxSteps)
        policy.makeLocalModel = {
            guard MLXBackend.modelDir(repo: MLXBackend.currentRepo) != nil else {
                throw HoldfastError("this needs private notes, which stay on this Mac, and no model is downloaded here")
            }
            onEvent(.step("Private notes stay on this Mac: continuing here"))
            ModelPrivacy.keptLocal = true
            return MLXAgentModel(backend: try await MLXBackend.shared())
        }
        // Connection errors stay visible; only the private policy switches to LocalMLX.
        let journal = try AgentJournal(directory: Config.stateDir.appendingPathComponent("agent-runs"),
                                       system: system, model: model.name, tools: tools, prior: history)
        let session = try AgentRuntime.Session(system: system, model: model, tools: registry, prior: history,
                                               localOnly: Profile.vaultDefault.id == Profile.privateNotes.id, policy: policy)
        let result = try await session.run(question, record: { try journal.append($0) }) { event in
            switch event {
            case .text(let text): onEvent(.token(text))
            case .assistant(let reply):
                let (thought, _) = Thinking.split(reply.text)
                let thinking = [reply.reasoning, thought].filter { !$0.isEmpty }.joined(separator: "\n\n")
                if !thinking.isEmpty { onEvent(.step("Thinking" + Steps.sep + thinking)) }
                if !reply.calls.isEmpty { onEvent(.resetText) }
            case .toolStarted(let call):
                onEvent(.step(ctx.title(call)))
            case .toolFinished(let call, let result):
                let detail = "\(call.name)(\(call.arguments))\n\n" + String(result.text.prefix(Steps.resultChars))
                    + (result.text.count > Steps.resultChars ? "\n[…]" : "")
                onEvent(.stepDetail(detail)); onEvent(.sources(ctx.sources))
            case .modelChanged: onEvent(.resetText)
            default: break
            }
        }
        var final = stripThoughts(Thinking.split(result.text).rest)
        let cited = (try? NSRegularExpression(pattern: #"\[(\d+)\]"#))?
            .matches(in: final, range: NSRange(final.startIndex..., in: final))
            .compactMap { Range($0.range(at: 1), in: final).flatMap { Int(final[$0]) } } ?? []
        var bad = Array(Set(cited.filter { $0 < 1 || $0 > ctx.sources.count })).sorted()
        if ctx.sources.isEmpty {
            final = final.replacingOccurrences(of: #"\s?\[\d+\]"#, with: "", options: .regularExpression)
            bad = []
        }
        return Answer(text: final, badCitations: bad, sources: ctx.sources,
                      stats: GenStats(promptTokens: result.usage.promptTokens, promptSeconds: result.usage.promptSeconds,
                                      outputTokens: result.usage.outputTokens, outputSeconds: result.usage.outputSeconds),
                      retrievalSeconds: Date().timeIntervalSince(t0), steps: ctx.log,
                      localOnly: ctx.touchedPrivateNotes || Profile.vaultDefault.id == Profile.privateNotes.id)
    }

}

/// Runs the tools and numbers what they return.
final class ToolContext: @unchecked Sendable {
    let embedder: Embedder?
    var sources: [Chunk] = []
    var log: [String] = []
    private lazy var tables = CSVTables()
    /// Set when a tool returned anything from private notes, folders or tables: a request on
    /// a server switches to LocalMLX before the result is sent.
    private(set) var touchedPrivateNotes = false
    /// The vault read once per Research run, not once per tool call.
    private lazy var vaultNotes: [Note] = allNotes()
    private lazy var inboxNotes: [Note] = allNotes(in: [Config.inboxDir])

    private func note(_ idOrPath: String) -> Note? {
        let key = idOrPath.hasSuffix(".md") ? String(idOrPath.dropLast(3)) : idOrPath
        let all = vaultNotes + inboxNotes
        return all.first { $0.id == key } ?? all.first { $0.name == key }
    }

    private func mark(_ relPaths: [String]) {
        if relPaths.contains(where: Profile.isPrivate) { touchedPrivateNotes = true }
    }

    /// Notes this run proposed changes to (waiting in the Inbox).
    private(set) var proposedEdits = Set<String>()
    /// Who the Inbox says proposed a change.
    var proposer = "Ask"

    init(embedder: Embedder?) { self.embedder = embedder }

    private func cite(_ c: Chunk) -> Int {
        // The same passage again gets its number; another passage of the same section gets its own.
        if let i = sources.firstIndex(where: { $0.relPath == c.relPath && $0.anchor == c.anchor && $0.text == c.text }) { return i + 1 }
        sources.append(c)
        return sources.count
    }

    func title(_ call: AgentRuntime.Call) -> String {
        let args = (try? JSONDecoder().decode([String: String].self, from: Data(call.arguments.utf8))) ?? [:]
        switch call.name {
        case "search": return "Searching: \(args["query"] ?? "")"
        case "read_note": return "Reading \(args["path"] ?? "")"
        case "list_folder": return "Listing \(args["path"].flatMap { $0.isEmpty ? nil : $0 } ?? "the vault")"
        case "list_tables": return "Listing tables"
        case "query_table": return "Querying: \(String((args["sql"] ?? "").prefix(80)))"
        case "propose_edit": return "Proposing a change to \(args["path"] ?? "")"
        default: return "Tool: \(call.name)"
        }
    }

    func call(_ name: String, args: [String: String], operationID: String? = nil) async -> String {
        func str(_ key: String) -> String { args[key] ?? "" }
        do {
            switch name {
            case "search":
                let q = str("query")
                log.append("search: \(q)")
                let hits = try await search(q, embedder: embedder, reranker: await Reranker.shared(), limit: 6)
                mark(hits.map(\.relPath))
                if hits.isEmpty { return "No relevant passages." }
                return hits.map { h in "[\(cite(h))] \(h.relPath) › \(h.anchor)\n\(h.text.prefix(900))" }.joined(separator: "\n\n")
            case "read_note":
                let p = str("path").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                log.append("read: \(p)")
                guard let n = note(p) ?? Packs.note(p) else { return "No note at \(p). Use list_folder to see what exists." }
                mark([n.relPath, n.meta["target"] ?? ""])
                var text = n.body
                if text.count > Agent.readChars { text = String(text.prefix(Agent.readChars)) + "\n[… truncated]" }
                let c = Chunk(noteId: n.id, relPath: n.relPath, title: n.title, anchor: n.title, text: text)
                return "[\(cite(c))] \(n.relPath)\n\(text)"
            case "list_folder":
                let p = str("path").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                log.append("list: \(p)")
                return listFolder(p)
            case "list_tables":
                let f = str("folder").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                log.append("tables: \(f)")
                mark(tables.files.filter { f.isEmpty || $0.hasPrefix(f + "/") })
                return tables.catalog(under: f)
            case "query_table":
                let sql = str("sql")
                log.append("sql: \(sql)")
                let (out, used) = try tables.query(sql, maxRows: Agent.maxRows)
                mark(used)
                if sql.lowercased().contains(CSVTables.propsTable), tables.propertiesIncludePrivateNotes { touchedPrivateNotes = true }
                let c = Chunk(noteId: used.joined(separator: ","), relPath: used.first ?? "data", title: "Query",
                              anchor: String(sql.prefix(120)), text: "SQL: \(sql)\n\(out)")
                return "[\(cite(c))] Query over \(used.joined(separator: ", "))\n\(out)"
            case "propose_edit":
                let p = str("path").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                log.append("edit: \(p)")
                mark([p])
                let out = try Edits.propose(path: p, old: str("old_text"), new: str("new_text"), why: str("why"), by: proposer, operationID: operationID)
                proposedEdits.insert(p)
                return out
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
        if !p.isEmpty, Profile.isPrivate(p) { touchedPrivateNotes = true }
        for n in vaultNotes where n.relPath.hasPrefix(prefix) {
            let rest = n.relPath.dropFirst(prefix.count)
            if let slash = rest.firstIndex(of: "/") { dirs.insert(String(rest[..<slash])) } else { files.append(n) }
        }
        let csvs = tables.files.filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }
        mark(files.map(\.relPath) + csvs)
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

    /// Whether the note_properties table holds any private note's properties.
    var propertiesIncludePrivateNotes: Bool { propertyNotes().contains { Profile.isPrivate($0.relPath) } }

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
        guard let head = rows.first, !head.isEmpty else { throw HoldfastError("\(path) is empty") }
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
            throw HoldfastError(m)
        }
    }

    /// Runs one SELECT; loads the tables it names first. Returns a pipe table.
    func query(_ sql: String, maxRows: Int) throws -> (String, [String]) {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: ";"))
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("select") || lower.hasPrefix("with"), !trimmed.contains(";") else {
            throw HoldfastError("only a single SELECT is allowed")
        }
        let used = files.filter { lower.contains(Self.tableName($0)) }
        let wantsProps = lower.contains(Self.propsTable)
        guard !used.isEmpty || wantsProps else { throw HoldfastError("no known table in the query; call list_tables first") }
        if wantsProps { try loadProperties() }
        for f in used { try load(f) }
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, trimmed, -1, &st, nil) == SQLITE_OK else {
            throw HoldfastError(String(cString: sqlite3_errmsg(db)))
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
