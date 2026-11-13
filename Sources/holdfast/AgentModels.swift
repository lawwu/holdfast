import Foundation
import MLXLMCommon
import LocalMLX
import ModelProviders

/// Holdfast adapter: policy and runtime types stay here; inference lives in LocalMLX.
final class MLXAgentModel: AgentRuntime.Model, @unchecked Sendable {
    let name: String
    let isLocal = true
    private let backend: MLXBackend
    private let engine: MLXSession
    private let allowsRebase: Bool
    let profile: ModelProviders.ModelProfile
    private var prefix: [AgentRuntime.Message] = []

    init(backend: MLXBackend, allowsRebase: Bool = false) {
        self.backend = backend
        name = backend.repo; self.allowsRebase = allowsRebase
        profile = backend.profile
        engine = MLXSession(container: backend.container, additionalContext: profile.templateContext, contextLimit: profile.contextTokens)
    }

    static func tool(_ spec: AgentRuntime.ToolSpec) -> MLXProtocol.Tool {
        .init(name: spec.name, description: spec.description, parameters: .object([
            "type": .string("object"), "properties": .object(spec.fields.mapValues {
                .object(["type": .string("string"), "description": .string($0)])
            }), "required": .array(spec.required.map { .string($0) }), "additionalProperties": .bool(false)
        ]))
    }

    func respondNative(_ request: MLXProtocol.Request, onText: @escaping @Sendable (String) -> Void) async throws -> AgentRuntime.Reply {
        var request = request; request.generation = profile.generation
        let reply = try await engine.respond(to: request, onText: onText)
        return try JSONDecoder().decode(AgentRuntime.Reply.self, from: JSONEncoder().encode(reply))
    }

    func respond(to request: AgentRuntime.Request, onText: @escaping @Sendable (String) -> Void) async throws -> AgentRuntime.Reply {
        if !allowsRebase, Array(request.messages.prefix(prefix.count)) != prefix {
            throw HoldfastError("the agent transcript changed underneath its MLX session")
        }
        let messages: [MLXProtocol.Message] = try request.messages.map { message in
            switch message {
            case .user(let text): return .init(role: "user", text: text)
            case .assistant(let reply):
                let calls = try reply.calls.map { call -> MLXProtocol.Call in
                    // Preserve invalid historical calls rejected by Holdfast's runtime
                    // during a remote→local handoff; the package itself accepts JSON objects.
                    let args = (try? JSONDecoder().decode([String: JSONValue].self, from: Data(call.arguments.utf8)))
                        ?? ["__invalid_json": .string(call.arguments)]
                    let raw = String(decoding: try JSONEncoder().encode(args), as: UTF8.self)
                    return .init(id: call.id, name: call.name, arguments: raw)
                }
                return .init(role: "assistant", text: reply.text, reasoning: reply.reasoning, calls: calls)
            case .tool(let call, let result): return .init(role: "tool", text: result.text, id: call.id, name: call.name)
            }
        }
        let reply = try await respondNative(.init(model: name, system: request.system, messages: messages,
            tools: request.tools.map(Self.tool), generation: profile.generation), onText: onText)
        prefix = request.messages + [.assistant(reply)]
        return reply
    }
}
