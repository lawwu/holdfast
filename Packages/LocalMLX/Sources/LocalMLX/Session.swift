import Foundation
import ModelProviders
import MLXLMCommon
import MLXLLM

/// Reuses an already-loaded model. Owns only its inference cache, never a vault,
/// tool implementation, approval queue, durable task, or application preference.
public actor MLXSession: ModelProvider {
    private let container: ModelContainer
    private let additionalContext: [String: any Sendable]
    private var session: ChatSession?
    private var previous: MLXProtocol.Request?
    private var prefix: [MLXProtocol.Message] = []
    private var busy = false
    private var prepared = false

    public init(container: ModelContainer, additionalContext: [String: any Sendable] = ["enable_thinking": false]) {
        self.container = container; self.additionalContext = additionalContext
    }

    public func respond(to request: MLXProtocol.Request, onText: @escaping @Sendable (String) -> Void) async throws -> MLXProtocol.Reply {
        guard !busy else { throw MLXProtocol.Failure("An inference request is already running") }
        busy = true; defer { busy = false }
        do {
            try Task.checkCancellation()
            guard request.version == 1 else { throw MLXProtocol.Failure("Unsupported Swift MLX protocol version") }
            if !prepared {
                await container.update { context in
                    if !(context.processor is JSONSafeInputProcessor) {
                        let generator = context.configuration.messageGenerator
                            ?? (context.model as? any LLMModel)?.messageGenerator(tokenizer: context.tokenizer)
                            ?? DefaultMessageGenerator()
                        context.processor = JSONSafeInputProcessor(base: context.processor, generator: generator)
                    }
                }
                prepared = true
            }
            let parameters = try request.generation.parameters()
            let messages = request.messages.map(\.normalized)
            if previous?.sessionID != request.sessionID || previous?.model != request.model
                || previous?.system != request.system || previous?.tools != request.tools
                || previous?.generation != request.generation || Array(messages.prefix(prefix.count)) != prefix {
                session = nil; prefix = []
            }
            if session == nil {
                session = ChatSession(container, instructions: request.system, generateParameters: parameters,
                                      additionalContext: additionalContext, tools: request.tools.map(\.wire))
            }
            let next = try messages.dropFirst(prefix.count).map(Self.chatMessage)
            guard !next.isEmpty else { throw MLXProtocol.Failure("No new messages to generate from") }
            var reply = MLXProtocol.Reply()
            for try await event in session!.streamDetails(to: next) {
                try Task.checkCancellation()
                switch event {
                case .chunk(let text): reply.text += text; onText(text)
                case .toolCall(let call):
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                    let data = try encoder.encode(call.function.arguments)
                    reply.calls.append(.init(id: call.id ?? UUID().uuidString, name: call.function.name,
                                             arguments: String(decoding: data, as: UTF8.self)))
                case .info(let info):
                    reply.usage.promptTokens = info.promptTokenCount; reply.usage.promptSeconds = info.promptTime
                    reply.usage.outputTokens = info.generationTokenCount; reply.usage.outputSeconds = info.generateTime
                    reply.truncated = info.stopReason == .length
                    if info.stopReason == .cancelled { throw CancellationError() }
                case .rejectedToolCall(let rejection): throw RejectedToolCallError(rejection)
                }
            }
            try Task.checkCancellation()
            prefix = messages + [MLXProtocol.Message(role: "assistant", text: reply.text, reasoning: reply.reasoning, calls: reply.calls).normalized]
            previous = request
            return reply
        } catch {
            // Cancellation/rejection can leave a partial cache; rebuild on the next call.
            session = nil; prefix = []; previous = nil
            throw error
        }
    }

    private static func chatMessage(_ message: MLXProtocol.Message) throws -> Chat.Message {
        switch message.role {
        case "user": return .user(message.text)
        case "assistant":
            let calls = try (message.calls ?? []).map { call in
                let args = try JSONDecoder().decode([String: JSONValue].self, from: Data(call.arguments.utf8))
                return ToolCall(function: .init(name: call.name, arguments: args), id: call.id)
            }
            let text = (message.reasoning.map { "<think>\($0)</think>" } ?? "") + message.text
            return .assistant(text, toolCalls: calls.isEmpty ? nil : calls)
        case "tool":
            guard let id = message.id, let name = message.name else { throw MLXProtocol.Failure("Tool result is missing its call ID/name") }
            return .tool(message.text, id: id, name: name)
        default: throw MLXProtocol.Failure("Unsupported message role: \(message.role)")
        }
    }
}

/// MLX's structured tool-call history uses JSONSerialization, whose NSNull and
/// NSNumber objects need normalizing before swift-jinja renders the template.
/// Preserve each model's own message layout, and use Swift Optional.none for a
/// genuine JSON null (Jinja accepts it); never turn null/false into strings or 0.
private struct JSONSafeInputProcessor: UserInputProcessor {
    let base: any UserInputProcessor
    let generator: any MessageGenerator
    func prepare(input: UserInput) async throws -> LMInput {
        var input = input
        input.prompt = .messages(generator.generate(from: input).map { $0.mapValues(Self.clean) })
        input.tools = input.tools?.map { $0.mapValues(Self.clean) }
        return try await base.prepare(input: input)
    }
    private static func clean(_ value: any Sendable) -> any Sendable {
        if value is NSNull { return Optional<String>.none as any Sendable }
        if let number = value as? NSNumber {
            switch JSONValue.from(number) {
            case .bool(let v): return v
            case .int(let v): return v
            case .double(let v): return v
            default: return value
            }
        }
        if let object = value as? [String: any Sendable] { return object.mapValues(clean) }
        if let array = value as? [any Sendable] { return array.map(clean) }
        return value
    }
}
