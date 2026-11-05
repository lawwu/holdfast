import Foundation

let usage = """
mackb — local knowledge base for counseling materials (POC)

  mackb ingest <file|folder|url> [--tag t]...   import docs (docx/pdf/md/txt), audio/video, or a YouTube URL
  mackb index [--force] [--no-embed]           (re)build the search index from the vault
  mackb search "<query>"                       hybrid keyword + semantic search
  mackb ask "<question>"                       answer with the local Qwen model, with citations
  mackb remember "<title>" "<text>"            propose a memory (goes to the inbox)
  mackb inbox | approve <id> | reject <id>     review agent-proposed memories
  mackb mcp                                    run the MCP server on stdio (for Claude Code etc.)
  mackb bench                                  measure LLM speed on a fixed prompt
  mackb eval [questions.json] --label <name>   score Q&A against a question set (see eval/)
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
        let q = args.joined(separator: " ")
        let a = try await ask(q, embedder: emb, llm: try await makeBackend()) { tok in
            FileHandle.standardOutput.write(tok.data(using: .utf8)!)
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
            if let f = n.meta["privacy_flags"] { print("    ⚠ \(f)") }
        }
    case "approve":
        let n = try approve(args.first ?? "")
        print("approved → \(n.relPath) (run `mackb index`)")
    case "reject":
        try reject(args.first ?? "")
        print("moved to Trash")
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
                          outDir: URL(fileURLWithPath: out), only: only)
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
