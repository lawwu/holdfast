import Foundation

/// Minimal MCP server over stdio (newline-delimited JSON-RPC 2.0).
/// Agents can read freely; anything they `remember` lands in the inbox for approval.
final class MCPServer {
    private var embedder: Embedder?
    private var embedderLoaded = false

    private func getEmbedder() async -> Embedder? {
        if !embedderLoaded {
            embedder = try? await Embedder.load()
            embedderLoaded = true
        }
        return embedder
    }

    static let tools: [[String: Any]] = [
        tool("search", "Hybrid keyword + semantic search over the counseling vault (lessons, homework, supervision notes, case reports). Returns passages with citations.",
             ["query": ["type": "string"], "limit": ["type": "integer", "default": 8]], required: ["query"]),
        tool("get_note", "Read one note in full by its id (from a search citation, e.g. [[id#anchor]]).",
             ["id": ["type": "string"]], required: ["id"]),
        tool("ask", "Answer a question from the vault with the local Qwen model, citing passages. Slower than search (tens of seconds).",
             ["question": ["type": "string"]], required: ["question"]),
        tool("remember", "Propose a memory note. It goes to the counselor's approval inbox, not straight into the vault. Use initials only for counselees.",
             ["title": ["type": "string"], "text": ["type": "string"], "tags": ["type": "array", "items": ["type": "string"]]],
             required: ["title", "text"]),
        tool("list_inbox", "List memory proposals still waiting for the counselor's approval.", [:], required: []),
    ]

    static func tool(_ name: String, _ desc: String, _ props: [String: Any], required: [String]) -> [String: Any] {
        ["name": name, "description": desc, "inputSchema": ["type": "object", "properties": props, "required": required]]
    }

    func serve() async {
        while let line = readLine(strippingNewline: true) {
            guard let d = line.data(using: .utf8), let msg = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            let id = msg["id"]
            let method = msg["method"] as? String ?? ""
            let params = msg["params"] as? [String: Any] ?? [:]
            if id == nil { continue }  // notification
            do {
                let result = try await handle(method, params)
                send(["jsonrpc": "2.0", "id": id!, "result": result])
            } catch {
                send(["jsonrpc": "2.0", "id": id!, "error": ["code": -32603, "message": "\(error)"]])
            }
        }
    }

    private func send(_ obj: [String: Any]) {
        if let d = try? JSONSerialization.data(withJSONObject: obj), let s = String(data: d, encoding: .utf8) {
            print(s)
            fflush(stdout)
        }
    }

    private func text(_ s: String, isError: Bool = false) -> [String: Any] {
        ["content": [["type": "text", "text": s]], "isError": isError]
    }

    private func handle(_ method: String, _ p: [String: Any]) async throws -> Any {
        switch method {
        case "initialize":
            return ["protocolVersion": (p["protocolVersion"] as? String) ?? "2025-06-18",
                    "capabilities": ["tools": [:]],
                    "serverInfo": ["name": "holdfast", "version": "0.1.0"]]
        case "ping": return [:]
        case "tools/list": return ["tools": Self.tools]
        case "tools/call":
            let name = p["name"] as? String ?? ""
            let a = p["arguments"] as? [String: Any] ?? [:]
            return try await call(name, a)
        default:
            throw HoldfastError("unknown method \(method)")
        }
    }

    private func call(_ name: String, _ a: [String: Any]) async throws -> [String: Any] {
        switch name {
        case "search":
            let q = a["query"] as? String ?? ""
            let hits = try await search(q, embedder: await getEmbedder(), reranker: await Reranker.shared(), limit: a["limit"] as? Int ?? 8)
            if hits.isEmpty { return text("No matches.") }
            return text(hits.enumerated().map { i, c in "[\(i + 1)] \(citation(c))\n\(c.text)" }.joined(separator: "\n\n---\n\n"))
        case "get_note":
            guard let n = findNote(a["id"] as? String ?? "") else { return text("No note with that id.", isError: true) }
            return text(try String(contentsOf: n.path, encoding: .utf8))
        case "ask":
            let ans = try await ask(a["question"] as? String ?? "", embedder: await getEmbedder(), llm: try await makeBackend())
            return text(ans.text + "\n" + formatSources(ans))
        case "remember":
            let tags = a["tags"] as? [String] ?? []
            let (n, flags) = try propose(title: a["title"] as? String ?? "Untitled", text: a["text"] as? String ?? "",
                                         tags: tags, by: "mcp-agent")
            var s = "Saved to the approval inbox as \(n.id). The counselor approves it with `holdfast approve \(n.id)`."
            if !flags.isEmpty { s += "\nPrivacy flags for the counselor to check: " + flags.joined(separator: "; ") }
            return text(s)
        case "list_inbox":
            let items = inbox()
            if items.isEmpty { return text("Inbox is empty.") }
            return text(items.map { "\($0.id): \($0.title)" + (($0.meta["privacy_flags"]).map { " ⚠ \($0)" } ?? "") }.joined(separator: "\n"))
        default:
            return text("Unknown tool \(name)", isError: true)
        }
    }
}
