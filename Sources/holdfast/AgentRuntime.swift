import Foundation

/// The model-independent part of an agent: conversation, tool dispatch and lifecycle.
/// Inspired by Pi's small agent core and Pennant's separation of inference, tools and
/// durable outcomes. No MLX, SwiftUI, vault paths or provider wire formats belong here.
enum AgentRuntime {
    struct Call: Codable, Sendable, Equatable {
        var id: String = UUID().uuidString
        var name: String
        /// Preserve the original JSON, including malformed arguments, for a repairable error.
        var arguments: String
    }

    struct ToolSpec: Codable, Sendable {
        var name: String
        var description: String
        /// The current vault tools accept named string fields, including SQL and exact text.
        var fields: [String: String]
        var required: [String]

        func validate(_ json: String) throws -> [String: String] {
            guard let args = try? JSONDecoder().decode([String: String].self, from: Data(json.utf8)) else {
                throw Failure("\(name) expects a JSON object with string values.")
            }
            for key in required where args[key] == nil {
                throw Failure("\(name) requires \(key).")
            }
            for key in args.keys.sorted() where fields[key] == nil {
                throw Failure("\(name) has no parameter named \(key).")
            }
            return args
        }

        var wireValue: [String: any Sendable] {
            ["type": "function", "function": [
                "name": name, "description": description,
                "parameters": ["type": "object",
                               "properties": fields.mapValues { ["type": "string", "description": $0] },
                               "required": required, "additionalProperties": false] as [String: any Sendable]
            ] as [String: any Sendable]]
        }
    }

    struct ToolResult: Codable, Sendable, Equatable {
        var text: String
        var isError = false
        /// Once any result is local-only, the whole conversation remains local-only.
        var localOnly = false
    }

    struct Tool: Sendable {
        var spec: ToolSpec
        var execute: @Sendable ([String: String]) async throws -> ToolResult
    }

    struct Usage: Codable, Sendable, Equatable {
        var promptTokens = 0
        var promptSeconds = 0.0
        var outputTokens = 0
        var outputSeconds = 0.0

        mutating func add(_ other: Usage) {
            promptTokens += other.promptTokens; promptSeconds += other.promptSeconds
            outputTokens += other.outputTokens; outputSeconds += other.outputSeconds
        }
    }

    struct Reply: Codable, Sendable, Equatable {
        var text = ""
        var reasoning = ""
        var calls: [Call] = []
        var usage = Usage()
        var truncated = false
    }

    enum Message: Codable, Sendable, Equatable {
        case user(String)
        case assistant(Reply)
        case tool(Call, ToolResult)
    }

    struct Request: Sendable {
        var system: String
        var messages: [Message]
        var tools: [ToolSpec]
        var localOnly: Bool
    }

    /// One instance per conversation. Adapters may retain an inference cache, but the
    /// runtime transcript is authoritative and can be passed to a replacement adapter.
    protocol Model: Sendable {
        var name: String { get }
        var isLocal: Bool { get }
        func respond(to request: Request, onText: @escaping @Sendable (String) -> Void) async throws -> Reply
    }

    enum Stop: String, Codable, Sendable { case completed, limit, cancelled, failed }
    enum Event: Codable, Sendable {
        case started
        case message(Message)
        case turnStarted(Int)
        case text(String)                  // transient; never journal token deltas
        case assistant(Reply)
        case toolStarted(Call)             // record intent BEFORE invoking the tool
        case toolFinished(Call, ToolResult)
        case turnFinished(Int)
        case modelChanged(String)
        case failed(String)
        case finished(Stop)
    }

    struct Result: Sendable {
        var text: String
        var usage: Usage
        var stop: Stop
    }

    struct Failure: LocalizedError {
        var errorDescription: String? { message }
        let message: String
        init(_ message: String) { self.message = message }
    }

    struct Policy: Sendable {
        var maxToolRounds = 8
        var maxToolCalls = 32
        var finalInstruction = "Answer now from what the tools returned, with [n] citations."
        var makeLocalModel: (@Sendable () async throws -> any Model)?
        /// Recovery retries only the failed model request, never completed tools. Nil refuses.
        var recoverModel: (@Sendable (any Error, any Model) async throws -> (any Model)?)?
    }

    /// Actor ownership keeps runs serial; a second prompt while running fails explicitly.
    /// Subsequent runs on the same session keep complete assistant/tool messages.
    actor Session {
        private var model: any Model
        private let system: String
        private let tools: [Tool]
        private let policy: Policy
        private var messages: [Message]
        private var localOnly: Bool
        private var running = false
        private var usable = true

        init(system: String, model: any Model, tools: [Tool], prior: [Message] = [],
             localOnly: Bool = false, policy: Policy = Policy()) throws {
            guard Set(tools.map { $0.spec.name }).count == tools.count else {
                throw Failure("Agent tool names must be unique.")
            }
            guard policy.maxToolRounds >= 0, policy.maxToolCalls >= 0 else {
                throw Failure("Agent limits cannot be negative.")
            }
            self.system = system; self.model = model; self.tools = tools; self.policy = policy
            self.messages = prior
            self.localOnly = localOnly || prior.contains {
                if case .tool(_, let result) = $0 { return result.localOnly }; return false
            }
        }

        func transcript() -> [Message] { messages }

        func run(_ question: String,
                 record: (@Sendable (Event) throws -> Void)? = nil,
                 onEvent: @escaping @Sendable (Event) -> Void = { _ in }) async throws -> Result {
            guard !running else { throw Failure("This agent session is already running.") }
            guard usable else { throw Failure("Start a new session after an interrupted or failed run; its tools are not replayed.") }
            running = true
            defer { running = false }
            func emit(_ event: Event) throws { try record?(event); onEvent(event) }
            var usage = Usage()
            var lastText = ""
            var callsUsed = 0
            do {
                try Task.checkCancellation()
                try emit(.started)
                let prompt = Message.user(question)
                try emit(.message(prompt)); messages.append(prompt)
                for round in 0...policy.maxToolRounds {
                    try Task.checkCancellation()
                    let finalTurn = round == policy.maxToolRounds || callsUsed >= policy.maxToolCalls
                    if finalTurn {
                        let instruction = Message.user(policy.finalInstruction)
                        try emit(.message(instruction)); messages.append(instruction)
                    }
                    try emit(.turnStarted(round))
                    let request = Request(system: system, messages: messages,
                                          tools: finalTurn ? [] : tools.map(\.spec), localOnly: localOnly)
                    if localOnly && !model.isLocal {
                        guard let makeLocal = policy.makeLocalModel else {
                            throw Failure("This conversation contains local-only material; a local model is required.")
                        }
                        model = try await makeLocal()
                        try emit(.modelChanged(model.name))
                    }
                    // Check again after selection: a policy callback cannot bypass locality.
                    guard !localOnly || model.isLocal else {
                        throw Failure("Local-only material cannot be sent to this model.")
                    }
                    try Task.checkCancellation()
                    let reply: Reply
                    do {
                        reply = try await model.respond(to: request) { onEvent(.text($0)) }
                    } catch {
                        try Task.checkCancellation()
                        guard let recover = policy.recoverModel,
                              let replacement = try await recover(error, model) else { throw error }
                        guard !localOnly || replacement.isLocal else {
                            throw Failure("Recovery cannot send local-only material to another Mac.")
                        }
                        model = replacement
                        try emit(.modelChanged(model.name))
                        try Task.checkCancellation()
                        reply = try await model.respond(to: request) { onEvent(.text($0)) }
                    }
                    try Task.checkCancellation()
                    usage.add(reply.usage)
                    lastText = reply.text
                    try emit(.assistant(reply)); messages.append(.assistant(reply))
                    if reply.calls.isEmpty {
                        let stop: Stop = finalTurn || reply.truncated ? .limit : .completed
                        try emit(.turnFinished(round)); try emit(.finished(stop))
                        return Result(text: lastText, usage: usage, stop: stop)
                    }
                    // Preserve an outcome for every call, even for bad arguments or cancellation.
                    // Tools execute sequentially: proposals to the same note depend on each other.
                    var ids = Set<String>()
                    var toolInterrupted = false
                    for call in reply.calls {
                        try emit(.toolStarted(call))
                        let result: ToolResult
                        if Task.isCancelled || toolInterrupted {
                            result = ToolResult(text: "Cancelled before execution.", isError: true)
                        } else if finalTurn || callsUsed >= policy.maxToolCalls {
                            result = ToolResult(text: "Tool budget exhausted; this call was not executed.", isError: true)
                        } else if reply.truncated {
                            result = ToolResult(text: "Response hit the output limit; re-issue the complete tool call.", isError: true)
                        } else if !ids.insert(call.id).inserted {
                            result = ToolResult(text: "Duplicate tool call id; this call was not executed.", isError: true)
                        } else if let tool = tools.first(where: { $0.spec.name == call.name }) {
                            callsUsed += 1
                            // A failed journal write must not get converted into a repairable
                            // tool error: stop the run before anything can be executed.
                            let args: [String: String]
                            do { args = try tool.spec.validate(call.arguments) }
                            catch {
                                let invalid = ToolResult(text: "Error: \(error.localizedDescription)", isError: true)
                                try emit(.toolFinished(call, invalid)); messages.append(.tool(call, invalid))
                                continue
                            }
                            do {
                                try Task.checkCancellation()
                                result = try await tool.execute(args)
                            } catch is CancellationError {
                                // An executing tool may have performed work before it observed
                                // cancellation. Never retry it or claim it had no effect.
                                toolInterrupted = true
                                result = ToolResult(text: "Tool interrupted; check its outcome before trying again.", isError: true)
                            } catch {
                                result = ToolResult(text: "Error: \(error.localizedDescription)", isError: true)
                            }
                        } else {
                            callsUsed += 1
                            result = ToolResult(text: "Unknown tool \(call.name). Use one of the available tools.", isError: true)
                        }
                        localOnly = localOnly || result.localOnly
                        try emit(.toolFinished(call, result)); messages.append(.tool(call, result))
                    }
                    try emit(.turnFinished(round))
                    if toolInterrupted { throw CancellationError() }
                    try Task.checkCancellation()
                    if finalTurn {
                        let text = "The model requested more tools after reaching the limit. Ask a narrower question."
                        try emit(.finished(.limit))
                        return Result(text: text, usage: usage, stop: .limit)
                    }
                    lastText = "" // a tool-call preamble is not a completed answer
                }
                throw Failure("Agent ended without a result.")
            } catch {
                usable = false
                if Task.isCancelled || error is CancellationError {
                    try emit(.finished(.cancelled))
                    return Result(text: "", usage: usage, stop: .cancelled)
                }
                try? emit(.failed(error.localizedDescription))
                try? emit(.finished(.failed))
                throw error
            }
        }
    }
}
