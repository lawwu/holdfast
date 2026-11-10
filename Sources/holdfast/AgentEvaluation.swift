import Foundation

/// Benchmark-only JSONL bridge. Uses the actual tools, source numbering and Inbox;
/// refuses to start without both an opt-in and a marked synthetic vault.
enum AgentEvaluation {
    static func serve() async throws {
        let marker = Config.vault.appendingPathComponent(".agent-eval-synthetic")
        guard ProcessInfo.processInfo.environment["HOLDFAST_AGENT_EVAL"] == "1",
              (try? String(contentsOf: marker, encoding: .utf8)) == "synthetic holdfast agent evaluation\n",
              ProcessInfo.processInfo.environment["HOLDFAST_PACKS"] == "none" else {
            throw HoldfastError("_agent-eval requires an explicitly marked synthetic vault and disabled packs")
        }
        try ensureVault()
        let context = ToolContext(embedder: nil)
        let system = [Profile.vaultDefault.systemPrompt, Agent.instructions, todayLine(), Agent.vaultOverview()].joined(separator: "\n\n")
        var journal: AgentJournal?
        while let line = readLine() {
            var response: [String: Any]
            do {
                let request = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] ?? [:]
                switch request["op"] as? String {
                case "config":
                    let specs = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Agent.tools))
                    response = ["system": system, "tools": specs, "stateDir": Config.stateDir.path,
                                "temperature": Config.temperature, "topP": Config.topP,
                                "topK": Config.topK, "presencePenalty": Config.presencePenalty,
                                "maxTokens": 2000, "maxToolRounds": Agent.maxSteps, "maxToolCalls": 32]
                case "call":
                    let name = request["name"] as? String ?? ""
                    guard let spec = Agent.tools.first(where: { $0.name == name }) else { throw HoldfastError("unknown tool \(name)") }
                    let data = try JSONSerialization.data(withJSONObject: request["arguments"] ?? [:])
                    let raw = String(decoding: data, as: UTF8.self)
                    let arguments = try spec.validate(raw)
                    if journal == nil {
                        journal = try AgentJournal(directory: Config.stateDir.appendingPathComponent("pi-tool-runs"),
                                                   system: system, model: "pi-evaluation", tools: Agent.tools, prior: [])
                    }
                    let call = AgentRuntime.Call(name: name, arguments: raw)
                    try journal!.append(.toolStarted(call))
                    let text = await context.call(name, args: arguments, operationID: request["operationID"] as? String)
                    let result = AgentRuntime.ToolResult(text: text, isError: text.hasPrefix("Error:"), localOnly: context.touchedPrivateNotes)
                    try journal!.append(.toolFinished(call, result))
                    response = ["text": text, "isError": result.isError, "localOnly": result.localOnly]
                case "run_pi":
                    guard let rawID = request["conversationID"] as? String, let conversationID = UUID(uuidString: rawID) else {
                        throw HoldfastError("run_pi needs a conversationID UUID")
                    }
                    let model: any AgentRuntime.Model
                    if let values = request["replies"] {
                        let replies = try JSONDecoder().decode([AgentRuntime.Reply].self, from: JSONSerialization.data(withJSONObject: values))
                        model = ScriptedPiModel(replies: replies, delayMS: request["delayMS"] as? Int ?? 0)
                    } else { model = MLXAgentModel(backend: try await MLXBackend.shared(), allowsRebase: true) }
                    let question = request["question"] as? String ?? ""
                    let task = Task { try await PiAgent.run(question, embedder: nil, model: model, conversationID: conversationID) { _ in } }
                    if let delay = request["cancelAfterMS"] as? Int {
                        Task { try? await Task.sleep(for: .milliseconds(delay)); task.cancel() }
                    }
                    let answer = try await task.value
                    response = ["answer": answer.text, "steps": answer.steps, "sources": answer.sources.map { ["path": $0.relPath, "text": $0.text] },
                                "badCitations": answer.badCitations, "promptTokens": answer.stats.promptTokens,
                                "outputTokens": answer.stats.outputTokens]
                case "run":
                    let started = Date()
                    let model: any AgentRuntime.Model
                    if request["engine"] as? String == "mlx" {
                        model = MLXAgentModel(backend: try await MLXBackend.shared())
                    } else if request["engine"] as? String == "ollama" {
                        model = ServerAgentModel(backend: try ServerBackend(kind: .custom))
                    } else { throw HoldfastError("unknown evaluation engine") }
                    let loaded = Date()
                    let answer = try await Agent.run(request["question"] as? String ?? "", embedder: nil, model: model) { _ in }
                    response = ["answer": answer.text, "loopSeconds": Date().timeIntervalSince(loaded),
                                "loadSeconds": loaded.timeIntervalSince(started), "steps": answer.steps,
                                "promptTokens": answer.stats.promptTokens, "outputTokens": answer.stats.outputTokens,
                                "promptSeconds": answer.stats.promptSeconds, "outputSeconds": answer.stats.outputSeconds,
                                "badCitations": answer.badCitations]
                default: throw HoldfastError("unknown evaluation operation")
                }
            } catch { response = ["error": String(describing: error)] }
            let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys, .fragmentsAllowed])
            FileHandle.standardOutput.write(data + Data([0x0A]))
        }
    }
}

// Only reachable behind serve()'s synthetic-vault guard. Tests exercise the real
// Pi process, SQLite, native tools and Inbox without needing the 27B model.
private actor ScriptedPiModel: AgentRuntime.Model {
    nonisolated let name = "holdfast-scripted-local-test"
    nonisolated let isLocal = true
    var replies: [AgentRuntime.Reply]
    let delayMS: Int
    init(replies: [AgentRuntime.Reply], delayMS: Int) { self.replies = replies; self.delayMS = delayMS }
    func respond(to request: AgentRuntime.Request, onText: @escaping @Sendable (String) -> Void) async throws -> AgentRuntime.Reply {
        if delayMS > 0 { try await Task.sleep(for: .milliseconds(delayMS)) }
        try Task.checkCancellation()
        guard !replies.isEmpty else { throw HoldfastError("Scripted Pi model ran out of responses") }
        let reply = replies.removeFirst(); onText(reply.text); return reply
    }
}
