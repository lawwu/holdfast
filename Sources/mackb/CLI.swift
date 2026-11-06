import Foundation

let usage = """
mackb — local knowledge base for counseling materials (POC)

  mackb ingest <file|folder|url> [--tag t]...   import docs (docx/pdf/md/txt), audio/video, or a YouTube URL
  mackb index [--force] [--no-embed]           (re)build the search index from the vault
  mackb search "<query>"                       hybrid keyword + semantic search
  mackb ask "<question>"                       answer with the local Qwen model, with citations
  mackb remember "<title>" "<text>"            propose a memory (goes to the inbox)
  mackb inbox | approve <id> | reject <id>     review agent-proposed memories and filings
  mackb drop [file...]                         file what is in the drop folder (adding these files first)
  mackb import <path...> [--as-is <folder>]   bulk import: file each one (default), or copy and convert into a folder
  mackb pack list | install <folder> | index <id> | on <id> | off <id> | remove <id>
                                               knowledge packs (read-only references Ask can quote)
  mackb pack create <id> --name N --license L --attribution A --source URL --cite C <files/folders...>
  mackb filings | undo <n>                     recent filings; undo the nth (1 = newest)
  mackb upcoming                               open follow-ups due soon or overdue
  mackb related <note.md>                      notes closest to a note (search embeddings)
  mackb rules                                  filing rules, and rules suggested from approvals
  mackb mcp                                    run the MCP server on stdio (for Claude Code etc.)
  mackb bench                                  measure LLM speed on a fixed prompt
  mackb eval [questions.json] --label <name>   score Q&A against a question set (see eval/)
                [--research] [--retrieval-only]   answer with the tool loop, or score search alone
  mackb eval-filing [filing.json] --label <name>  score where dropped documents get filed (eval/household/)
  mackb status                                 vault and index counts

Vault: $MACKB_VAULT (default ~/MacKB). LLM: $MACKB_BACKEND=ollama|mlx; Ollama model $MACKB_LLM
(default qwen38-27b-q8-32k), MLX model $MACKB_MLX_REPO (default mlx-community/Qwen3.8-27B-4bit).
"""

nonisolated(unsafe) var args = Array(CommandLine.arguments.dropFirst())
func flag(_ f: String) -> Bool {
    if let i = args.firstIndex(of: f) { args.remove(at: i); return true }
    return false
}
func option(_ f: String) -> [String] {
    var out: [String] = []
    while let i = args.firstIndex(of: f), i + 1 < args.count {
        out.append(args[i + 1])
        args.removeSubrange(i...(i + 1))
    }
    return out
}

func runCLI() async {
do {
    guard let cmd = args.first else { print(usage); exit(0) }
    args.removeFirst()
    try ensureVault()
    switch cmd {
    case "ingest":
        let tags = option("--tag")
        let title = option("--title").first
        guard let target = args.first else { throw MacKBError("ingest what?") }
        if target.hasPrefix("http://") || target.hasPrefix("https://") {
            let n = try await ingestURL(target, tags: tags)
            print("→ \(n.relPath)")
        } else {
            let u = URL(fileURLWithPath: (target as NSString).expandingTildeInPath).standardizedFileURL
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) else { throw MacKBError("not found: \(u.path)") }
            if isDir.boolValue {
                let t0 = Date()
                let r = try ingestFolder(u, tags: tags)
                print(String(format: "imported %d documents in %.1fs (%d duplicate docx/pdf copies skipped)", r.ok, Date().timeIntervalSince(t0), r.skipped))
                for f in r.failed { print("  ! \(f)") }
            } else if audioExtensions.contains(u.pathExtension.lowercased()) {
                let n = try await ingestAudio(u, title: title, tags: tags)
                print("→ \(n.relPath)")
            } else {
                let n = try ingestDocument(u, root: nil, tags: tags)
                print("→ \(n.relPath)")
            }
        }
        print("run `mackb index` to make new notes searchable")
    case "index":
        let force = flag("--force")
        let emb = flag("--no-embed") ? nil : try await Embedder.load()
        try await reindex(embedder: emb, force: force)
    case "search":
        let emb = flag("--no-embed") ? nil : try await Embedder.load()
        let q = args.joined(separator: " ")
        for (i, c) in try await search(q, embedder: emb, reranker: await Reranker.shared(), limit: 8).enumerated() {
            let preview = c.text.split(separator: "\n").dropFirst().joined(separator: " ").prefix(220)
            print("[\(i + 1)] \(citation(c))" + (c.score.map { String(format: "  (%.2f)", $0) } ?? "") + "\n    \(preview)\n")
        }
    case "ask":
        let emb = flag("--no-embed") ? nil : try await Embedder.load()
        let research = flag("--research")
        let q = args.joined(separator: " ")
        let a: Answer
        if research {
            // Tool loop on MLX: steps go to stderr, the answer to stdout at the end.
            a = try await Agent.run(q, embedder: emb, backend: try await MLXBackend.shared()) { ev in
                if case .step(let s) = ev { log("  → \(s)") }
            }
            print(a.text)
        } else {
            a = try await ask(q, embedder: emb, llm: try await makeBackend()) { tok in
                FileHandle.standardOutput.write(tok.data(using: .utf8)!)
            }
        }
        print("\n" + formatSources(a))
        log(String(format: "retrieval %.2fs · prompt %d tok at %.0f tok/s · answer %d tok at %.1f tok/s",
                   a.retrievalSeconds, a.stats.promptTokens, a.stats.promptTokPerSec, a.stats.outputTokens, a.stats.tokPerSec))
    case "remember":
        let tags = option("--tag")
        guard args.count >= 2 else { throw MacKBError("remember \"<title>\" \"<text>\"") }
        let (n, flags) = try propose(title: args[0], text: args[1], tags: tags, by: "cli")
        print("inbox: \(n.id)")
        for f in flags { print("  ⚠ \(f)") }
    case "inbox":
        let items = inbox()
        if items.isEmpty { print("inbox empty") }
        for n in items {
            print("\(n.id)  \(n.title)  (by \(n.meta["proposed_by"] ?? "?"))")
            if let t = n.meta["target"] { print("    → \(n.meta["action"] ?? "new") \(t): \(n.meta["why"] ?? "")") }
            if let f = n.meta["privacy_flags"] { print("    ⚠ \(f)") }
        }
    case "approve":
        let n = try approve(args.first ?? "")
        print("approved → \(n.relPath) (run `mackb index`)")
    case "reject":
        try reject(args.first ?? "")
        print("moved to Trash")
    case "import":
        let asIs = option("--as-is").first
        let urls = args.map { URL(fileURLWithPath: $0) }
        if let folder = asIs {
            let r = await BulkImport.asIs(urls, into: folder) { done, total, file in
                if !file.isEmpty { FileHandle.standardError.write(Data("[\(done + 1)/\(total)] \(file)\n".utf8)) }
            }
            print("imported \(r.notes) notes and \(r.tables) tables into \(r.folder)/; skipped \(r.skipped.count)")
            for s in r.skipped.prefix(20) { print("  skipped: \(s)") }
        } else {
            let r = try BulkImport.queue(urls)
            print("queued \(r.queued) files in the drop folder (skipped \(r.skipped.count)); run `mackb drop` to file them")
        }
    case "pack":
        let sub = args.first ?? "list"
        let rest = Array(args.dropFirst())
        switch sub {
        case "list":
            let on = Packs.enabled()
            for m in Packs.installed() {
                let c = Packs.count(m.id)
                print("\(on.contains(m.id) ? "on " : "off") \(m.id)  \(m.name) · \(m.license) · " + (c.map { "\($0.notes) notes, \($0.chunks) passages" } ?? "not indexed"))
            }
        case "install":
            let m = try Packs.install(from: URL(fileURLWithPath: rest.first ?? "."))
            print("installed \(m.id) (\(m.name)); run `mackb pack index \(m.id)` then `mackb pack on \(m.id)`")
        case "index":
            let emb = try? await Embedder.load()
            try await Packs.reindex(rest.first ?? "", embedder: emb, force: flag("--force"))
            if let c = Packs.count(rest.first ?? "") { print("\(c.notes) notes, \(c.chunks) passages, \(c.vectors) with vectors") }
        case "on", "off":
            Packs.setEnabled(rest.first ?? "", sub == "on")
            print("\(rest.first ?? "") \(sub)")
        case "remove":
            try Packs.remove(rest.first ?? "")
            print("moved to Trash")
        case "create":
            var r = rest
            func opt(_ k: String) -> String {
                guard let i = r.firstIndex(of: k), i + 1 < r.count else { return "" }
                let v = r[i + 1]; r.removeSubrange(i...(i + 1)); return v
            }
            let id = r.removeFirst()
            let name = opt("--name"), lic = opt("--license"), att = opt("--attribution"), src = opt("--source"), cite = opt("--cite")
            let report = try await Packs.create(id: id, name: name.isEmpty ? id : name, license: lic, attribution: att, source: src,
                                                description: opt("--description"), cite: cite.isEmpty ? id : cite,
                                                from: r.map { URL(fileURLWithPath: $0) })
            print("pack \(id): \(report.notes) notes; skipped \(report.skipped.count). Run `mackb pack index \(id)`.")
        default:
            throw MacKBError("pack list | install | index | on | off | remove | create")
        }
    case "filings":
        for (i, r) in FilingLog.load().prefix(20).enumerated() {
            print("\(i + 1). \(r.undone ? "[undone] " : "")\(r.action) \(r.target)  \(r.title)\(r.rule.map { "  (rule: \($0))" } ?? "")")
        }
    case "undo":
        let rs = FilingLog.load()
        guard let k = Int(args.first ?? "1"), k >= 1, k <= rs.count else { throw MacKBError("undo <n>: see `mackb filings`") }
        print(try FilingLog.undo(rs[k - 1].id))
    case "upcoming":
        let items = Upcoming.scan(allNotes())
        if items.isEmpty { print("nothing due in the next \(Upcoming.horizonDays) days") }
        for f in items { print("\(f.due)\(f.overdue ? " (overdue)" : "")  \(f.text)  — \(f.note.relPath)") }
    case "related":
        for r in try Related.find(args.first ?? "") { print(String(format: "%3.0f%%  %@", r.score * 100, r.relPath)) }
    case "rules":
        let rules = Rules.load()
        print(rules.isEmpty ? "no rules (\(Rules.url.path))" : "rules (\(Rules.url.path)):")
        for r in rules { print("  \"\(r.match)\" → \(r.action) \(r.target)\(r.auto ? " (auto)" : "")") }
        for c in Rules.suggestions() { print("  suggested: \"\(c.from)\" → \(c.action) \(c.target) (\(c.count) approvals)") }
    case "drop":
        try Drop.add(args.map { URL(fileURLWithPath: $0) })
        let files = Drop.pending(settled: false)
        if files.isEmpty { print("drop folder is empty: \(Drop.dir.path)") }
        let emb = try? await Embedder.load()
        let llm: LLMBackend? = Config.inPlace ? try await makeBackend() : nil
        for u in files {
            do { print("\(u.lastPathComponent): " + (try await Drop.process(u, embedder: emb, llm: llm, model: "cli"))) }
            catch let e as AlreadyFiled { print("\(u.lastPathComponent): skipped, \(e)") }
            catch { print("\(u.lastPathComponent): failed — \(error)") }
        }
    case "mcp":
        await MCPServer().serve()
    case "bench":
        let prompt = "In about 150 words, explain what the 'put off / put on' pattern in Ephesians 4:22-24 means for someone fighting anger."
        for run in 1...2 {
            let s = try await makeBackend().chat(system: "You are concise.", user: prompt) { _ in }
            print(String(format: "run %d: prompt %d tok at %.0f tok/s · output %d tok at %.1f tok/s", run,
                         s.promptTokens, s.promptTokPerSec, s.outputTokens, s.tokPerSec))
        }
    case "eval":
        let label = option("--label").first ?? "run"
        let only = Set(option("--only"))
        let out = option("--out").first ?? "eval/results"
        try await runEval(questionsPath: args.first ?? "eval/questions.json", label: label,
                          outDir: URL(fileURLWithPath: out), only: only,
                          research: flag("--research"), retrievalOnly: flag("--retrieval-only"))
    case "eval-filing":
        let label = option("--label").first ?? "run"
        try await runFilingEval(casesPath: args.first ?? "eval/household/filing.json", label: label,
                                outDir: URL(fileURLWithPath: option("--out").first ?? "eval/household/results/filing"),
                                only: Set(option("--only")))
    case "status":
        let idx = try Index()
        let c = idx.count()
        print("vault: \(Config.vault.path)")
        print("notes: \(allNotes().count) · inbox: \(inbox().count) · indexed: \(c.notes) notes, \(c.chunks) chunks, \(c.vectors) vectors")
    default:
        print(usage)
    }
} catch {
    log("error: \(error)")
    exit(1)
}
}
