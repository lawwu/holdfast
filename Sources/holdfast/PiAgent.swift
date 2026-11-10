import Darwin
import Foundation
import LocalMLX

/// Regular Pi owns the saved conversation and tool loop. This bridge owns inference
/// adapters and Holdfast's tool boundary; it exposes no general file/process tools.
enum PiAgent {
    // Pi is the app and CLI default. Keep the Swift loop as an explicit development override.
    static var enabled: Bool { ProcessInfo.processInfo.environment["HOLDFAST_AGENT_HARNESS"] != "swift" }
    static var directory: URL { Config.stateDir.appendingPathComponent("pi") }
    static var legacyDirectory: URL { Config.stateDir.appendingPathComponent("pi-durable") }

    struct Pending: Codable, Identifiable {
        var conversationID: UUID
        var requestID: UUID
        var question: String
        var date = Date()
        var id: UUID { conversationID }
    }
    static var pending: [Pending] {
        let dirs = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { try? JSONDecoder().decode(Pending.self, from: Data(contentsOf: $0.appendingPathComponent("pending.json"))) }
            .sorted { $0.date > $1.date }
    }

    static func helper() throws -> (node: URL, runner: URL) {
        let env = ProcessInfo.processInfo.environment
        let nodes = [env["HOLDFAST_NODE"], "/opt/homebrew/bin/node", "/usr/local/bin/node"]
            .compactMap { $0 } + (env["PATH"] ?? "").split(separator: ":").map { "\($0)/node" }
        guard let node = nodes.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw HoldfastError("Pi needs Node 22.19 or newer. Set HOLDFAST_NODE to its full path.")
        }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let roots = [env["HOLDFAST_PI_DIR"].map { URL(fileURLWithPath: $0) },
                     Bundle.main.resourceURL?.appendingPathComponent("pi"),
                     source.appendingPathComponent("Runtime/pi")].compactMap { $0 }
        guard let root = roots.first(where: {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("runner.mjs").path)
                && FileManager.default.fileExists(atPath: $0.appendingPathComponent("node_modules/@earendil-works/pi-coding-agent/package.json").path)
        }) else { throw HoldfastError("Install Pi with npm ci --ignore-scripts in Runtime/pi, or set HOLDFAST_PI_DIR.") }
        return (URL(fileURLWithPath: node), root.appendingPathComponent("runner.mjs"))
    }

    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func run(_ question: String, embedder: Embedder?, backend: MLXBackend, conversationID: UUID = UUID(),
                    requestID: UUID? = nil, prior: [(q: String, a: String)] = [],
                    onEvent: @escaping @Sendable (Agent.Event) -> Void) async throws -> Answer {
        try await run(question, embedder: embedder, model: MLXAgentModel(backend: backend, allowsRebase: true),
                      conversationID: conversationID, requestID: requestID, prior: prior, onEvent: onEvent)
    }

    static func run(_ question: String, embedder: Embedder?, model: any AgentRuntime.Model, conversationID: UUID,
                    requestID: UUID? = nil, prior: [(q: String, a: String)] = [],
                    onEvent: @escaping @Sendable (Agent.Event) -> Void) async throws -> Answer {
        let paths = try helper()
        let dir = directory.appendingPathComponent(conversationID.uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let lock = Darwin.open(dir.appendingPathComponent("lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw HoldfastError("Cannot lock the Pi conversation") }
        defer { Darwin.close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw HoldfastError("This Pi conversation is already running") }
        let pendingURL = dir.appendingPathComponent("pending.json")
        let request = Pending(conversationID: conversationID, requestID: requestID ?? UUID(), question: question)
        try save(request, to: pendingURL)
        let service = try PiNativeService(directory: dir, embedder: embedder, model: model, onEvent: onEvent)
        let pipe = PiPipe()
        let lines = try pipe.start(node: paths.node, runner: paths.runner)
        defer { pipe.close() }
        let sessions = dir.appendingPathComponent("sessions")
        let fresh = !((try? FileManager.default.contentsOfDirectory(atPath: sessions.path)) ?? []).contains { $0.hasSuffix(".jsonl") }
        var config: [String: Any] = ["type": "start", "protocol": 1, "sessionDirectory": sessions.path,
                                    "model": model.name, "contextWindow": (model as? ServerAgentModel)?.backend.configuration.contextWindow ?? 32768,
                                    "generation": ["maxTokens": 2000, "temperature": Config.temperature, "topP": Config.topP,
                                                   "topK": Config.topK, "presencePenalty": Config.presencePenalty],
                                    "system": [Profile.vaultDefault.systemPrompt, Agent.instructions, todayLine(), Agent.vaultOverview()].joined(separator: "\n\n"),
                                    "tools": try JSONSerialization.jsonObject(with: JSONEncoder().encode(Agent.tools)),
                                    "question": question, "requestID": request.requestID.uuidString]
        if fresh && !prior.isEmpty {
            config["handoff"] = "Earlier conversation (context only; earlier requests are already handled):\n" + prior.suffix(Conversation.turns)
                .map { "User: \($0.q)\nAssistant: \($0.a.prefix(Conversation.answerChars))" }.joined(separator: "\n\n")
        }
        try pipe.send(config)
        onEvent(.step("Pi · " + (model.isLocal ? "LocalMLX on this Mac" : model.name)))
        do { return try await withTaskCancellationHandler {
            for await data in lines {
                try Task.checkCancellation()
                guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                switch value["type"] as? String {
                case "request":
                    guard let id = value["id"] as? String, let method = value["method"] as? String else { throw HoldfastError("Invalid Pi request") }
                    let params = try JSONSerialization.data(withJSONObject: value["params"] ?? [:])
                    let task = Task {
                        do {
                            let result = try await service.respond(method: method, data: params) { text in
                                try? pipe.send(["type": "delta", "id": id, "text": text])
                            }
                            try Task.checkCancellation()
                            try pipe.send(["type": "response", "id": id, "result": try JSONSerialization.jsonObject(with: result)])
                        } catch {
                            try? pipe.send(["type": "response", "id": id, "error": error.localizedDescription])
                        }
                    }
                    pipe.track(id, task)
                case "cancel": if let id = value["id"] as? String { pipe.cancel(id) }
                case "done":
                    try? FileManager.default.removeItem(at: pendingURL)
                    return await service.answer(value["text"] as? String ?? "")
                case "error":
                    try? FileManager.default.removeItem(at: pendingURL)
                    throw HoldfastError(value["message"] as? String ?? "Pi helper failed")
                default: break
                }
            }
            try Task.checkCancellation()
            throw HoldfastError("Pi helper stopped. The conversation and existing proposals are saved. Ask a new question to continue (conversation \(conversationID.uuidString)).")
        } onCancel: {
            // Stop cancels the current Pi turn and native inference; no job is replayed later.
            pipe.abort()
            try? FileManager.default.removeItem(at: pendingURL)
        }
        } catch {
            // A CLI caller may exit as soon as we return. Give the helper time to
            // finish cancellation before releasing the conversation lock or exiting.
            if Task.isCancelled { await pipe.waitForAbort() }
            throw error
        }
    }
}

private actor PiNativeService {
    struct Receipt: Codable { var input: String; var result: AgentRuntime.ToolResult }
    struct State: Codable { var sources: [Chunk] = []; var receipts: [String: Receipt] = [:]; var localOnly: Bool? = nil }
    private var state: State
    private let stateURL: URL
    private let ctx: ToolContext
    private let model: any AgentRuntime.Model
    private var localModel: MLXAgentModel?
    private let onEvent: @Sendable (Agent.Event) -> Void
    private let started = Date()
    private var usage = AgentRuntime.Usage()
    private var busy = false
    private var calls = 0
    private var requiresLocal: Bool {
        state.localOnly == true || ctx.touchedCounseling || ModelPrivacy.touchesCounseling(state.sources)
            || state.receipts.values.contains { $0.result.localOnly } || Profile.vaultDefault.id == Profile.counseling.id
    }

    init(directory: URL, embedder: Embedder?, model: any AgentRuntime.Model, onEvent: @escaping @Sendable (Agent.Event) -> Void) throws {
        self.model = model; self.onEvent = onEvent
        stateURL = directory.appendingPathComponent("native.json")
        if FileManager.default.fileExists(atPath: stateURL.path) { state = try JSONDecoder().decode(State.self, from: Data(contentsOf: stateURL)) }
        else {
            let legacy = PiAgent.legacyDirectory.appendingPathComponent(directory.lastPathComponent).appendingPathComponent("native.json")
            // Preserve privacy and source numbering when an old conversation is continued.
            // Read the old sidecar only; Durable SQLite, pending jobs and proposals are untouched.
            if FileManager.default.fileExists(atPath: legacy.path) {
                state = try JSONDecoder().decode(State.self, from: Data(contentsOf: legacy))
                try PiAgent.save(state, to: stateURL)
            } else { state = State() }
        }
        ctx = ToolContext(embedder: embedder); ctx.proposer = "Ask · Pi"; ctx.sources = state.sources
    }

    func respond(method: String, data: Data, onDelta: @escaping @Sendable (String) -> Void) async throws -> Data {
        guard !busy else { throw HoldfastError("Concurrent native requests are disabled in Holdfast") }
        busy = true; defer { busy = false }
        try Task.checkCancellation()
        if method == "model" {
            let localOnly = requiresLocal
            if localOnly && !model.isLocal && localModel == nil {
                onEvent(.step("Counseling notes stay on this Mac: continuing with LocalMLX"))
                localModel = MLXAgentModel(backend: try await MLXBackend.shared(), allowsRebase: true)
                ModelPrivacy.keptLocal = true
            }
            var input = try JSONDecoder().decode(MLXProtocol.Request.self, from: data)
            guard input.version == 1, input.model == model.name else { throw HoldfastError("Unsupported inference model or protocol") }
            let messages: [AgentRuntime.Message] = try input.messages.map { m in
                switch m.role {
                case "user": return .user(m.text)
                case "assistant": return .assistant(.init(text: m.text, reasoning: m.reasoning ?? "", calls: (m.calls ?? []).map {
                    .init(id: $0.id, name: $0.name, arguments: $0.arguments)
                }))
                case "tool":
                    guard let id = m.id, let name = m.name else { throw HoldfastError("Missing Pi tool result identity") }
                    return .tool(.init(id: id, name: name, arguments: ""), .init(text: m.text, localOnly: localOnly))
                default: throw HoldfastError("Unsupported Pi message role")
                }
            }
            let tools = try input.tools.map { declaration in
                guard let spec = Agent.tools.first(where: { $0.name == declaration.name }), MLXAgentModel.tool(spec) == declaration else {
                    throw HoldfastError("Pi requested an unknown or changed native tool: \(declaration.name)")
                }
                return spec
            }
            onEvent(.resetText)
            let stream: @Sendable (String) -> Void = { [onEvent] text in
                onDelta(text); onEvent(.token(text))
            }
            let reply: AgentRuntime.Reply
            if let localModel {
                input.model = localModel.name
                reply = try await localModel.respondNative(input, onText: stream)
            } else if let native = model as? MLXAgentModel { reply = try await native.respondNative(input, onText: stream) }
            else if let server = model as? ServerAgentModel { reply = try await server.respondNative(input, onText: stream) }
            else { reply = try await model.respond(to: .init(system: input.system, messages: messages, tools: tools, localOnly: localOnly), onText: stream) }
            // Holdfast policy belongs here, before any harness schema coercion.
            for call in reply.calls {
                guard let spec = tools.first(where: { $0.name == call.name }) else { throw HoldfastError("Model requested an unavailable Holdfast tool") }
                _ = try spec.validate(call.arguments)
            }
            usage.add(reply.usage)
            if !reply.calls.isEmpty { onEvent(.resetText) }
            return try JSONEncoder().encode(reply)
        }
        guard method == "tool" else { throw HoldfastError("Unknown Pi bridge method") }
        struct Input: Decodable { var name: String; var args: [String: String]; var operationID: String }
        let input = try JSONDecoder().decode(Input.self, from: data)
        guard input.operationID.count <= 200, !input.operationID.isEmpty,
              input.operationID.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_:.")).contains($0) }) else {
            throw HoldfastError("Invalid Pi operation identity")
        }
        let canonical = String(decoding: try JSONSerialization.data(withJSONObject: JSONSerialization.jsonObject(with: data), options: [.sortedKeys]), as: UTF8.self)
        if let receipt = state.receipts[input.operationID] {
            guard receipt.input == canonical else { throw HoldfastError("Pi reused a tool operation ID with different arguments") }
            onEvent(.sources(state.sources))
            return try JSONEncoder().encode(receipt.result)
        }
        calls += 1
        guard calls <= 32 else { throw HoldfastError("Pi reached Holdfast's 32-call limit") }
        guard let spec = Agent.tools.first(where: { $0.name == input.name }) else { throw HoldfastError("Unknown Holdfast tool") }
        let argsData = try JSONEncoder().encode(input.args)
        let raw = String(decoding: argsData, as: UTF8.self)
        let args = try spec.validate(raw)
        let call = AgentRuntime.Call(id: input.operationID, name: input.name, arguments: raw)
        onEvent(.step(ctx.title(call)))
        let operation = stateURL.deletingLastPathComponent().lastPathComponent + "." + input.operationID
        let text = await ctx.call(input.name, args: args, operationID: operation)
        let result = AgentRuntime.ToolResult(text: text, isError: text.hasPrefix("Error:"), localOnly: ctx.touchedCounseling)
        state.localOnly = state.localOnly == true || ctx.touchedCounseling
        state.sources = ctx.sources; state.receipts[input.operationID] = Receipt(input: canonical, result: result)
        try PiAgent.save(state, to: stateURL) // Before acknowledging the tool to Pi.
        onEvent(.stepDetail("\(input.name)(\(raw))\n\n\(text.prefix(Steps.resultChars))")); onEvent(.sources(ctx.sources))
        return try JSONEncoder().encode(result)
    }

    func answer(_ text: String) -> Answer {
        var final = stripThoughts(Thinking.split(text).rest)
        let cited = (try? NSRegularExpression(pattern: #"\[(\d+)\]"#))?.matches(in: final, range: NSRange(final.startIndex..., in: final))
            .compactMap { Range($0.range(at: 1), in: final).flatMap { Int(final[$0]) } } ?? []
        let bad = Array(Set(cited.filter { $0 < 1 || $0 > ctx.sources.count })).sorted()
        if ctx.sources.isEmpty { final = final.replacingOccurrences(of: #"\s?\[\d+\]"#, with: "", options: .regularExpression) }
        return Answer(text: final, badCitations: ctx.sources.isEmpty ? [] : bad, sources: ctx.sources,
                      stats: .init(promptTokens: usage.promptTokens, promptSeconds: usage.promptSeconds, outputTokens: usage.outputTokens, outputSeconds: usage.outputSeconds),
                      retrievalSeconds: Date().timeIntervalSince(started), steps: ctx.log,
                      localOnly: requiresLocal)
    }
}

private final class PiPipe: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe(), output = Pipe()
    private let lock = NSLock()
    private var tasks: [String: Task<Void, Never>] = [:]
    private var stopped = false
    private var aborting = false

    func start(node: URL, runner: URL) throws -> AsyncStream<Data> {
        process.executableURL = node; process.arguments = [runner.path]
        process.currentDirectoryURL = runner.deletingLastPathComponent()
        process.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin", "NODE_NO_WARNINGS": "1"]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.standardError
        // A dead helper should produce a recoverable error, never SIGPIPE the app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        var continuation: AsyncStream<Data>.Continuation!
        let stream = AsyncStream<Data> { continuation = $0 }
        try process.run()
        let consumer = continuation!
        DispatchQueue.global(qos: .userInitiated).async { [output] in
            var buffer = Data()
            while true {
                let next = output.fileHandleForReading.availableData
                if next.isEmpty { break }
                buffer.append(next)
                while let end = buffer.firstIndex(of: 10) {
                    consumer.yield(Data(buffer[..<end])); buffer.removeSubrange(...end)
                }
                if buffer.count > 32 * 1024 * 1024 { break }
            }
            consumer.finish()
        }
        return stream
    }

    func send(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value) + Data([10])
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { throw HoldfastError("Pi bridge is closed") }
        try input.fileHandleForWriting.write(contentsOf: data)
    }
    func track(_ id: String, _ task: Task<Void, Never>) {
        lock.lock(); defer { lock.unlock() }
        if stopped || aborting { task.cancel() } else { tasks[id] = task }
    }
    func cancel(_ id: String) { lock.lock(); let task = tasks[id]; lock.unlock(); task?.cancel() }
    func abort() {
        lock.lock(); aborting = true; lock.unlock()
        try? send(["type": "abort"])
        lock.lock(); let running = Array(tasks.values); lock.unlock()
        running.forEach { $0.cancel() }
        // Leave a short window for Pi to persist the abort before closing its pipes.
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [self] in close(force: true) }
    }
    func waitForAbort() async {
        let end = Date().addingTimeInterval(4)
        while process.isRunning && Date() < end {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { continuation.resume() }
            }
        }
    }
    func close(force: Bool = false) {
        lock.lock()
        if stopped || (aborting && !force) { lock.unlock(); return }
        stopped = true; let running = Array(tasks.values); tasks.removeAll(); lock.unlock()
        running.forEach { $0.cancel() }
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [process] in
                if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            }
        }
    }
}
