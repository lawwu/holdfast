import Foundation

/// Versioned, inference-only wire types shared by embedded and subprocess hosts.
/// Tool definitions describe what the model can request; this package never executes tools.
public enum Inference {
    public struct Failure: LocalizedError, Sendable {
        public var errorDescription: String?
        public init(_ message: String) { errorDescription = message }
    }
    public struct Tool: Codable, Sendable, Equatable {
        public var name: String
        public var description: String
        public var parameters: ModelJSON
        public init(name: String, description: String, parameters: ModelJSON) {
            self.name = name; self.description = description; self.parameters = parameters
        }
    }
    public struct Call: Codable, Sendable, Equatable {
        public var id: String
        public var name: String
        /// A JSON object, preserved without coercing numbers, booleans, arrays or nulls.
        public var arguments: String
        public init(id: String, name: String, arguments: String) { self.id = id; self.name = name; self.arguments = arguments }
    }
    public struct Message: Codable, Sendable, Equatable {
        public var role: String
        public var text: String
        public var reasoning: String?
        public var calls: [Call]?
        public var id: String?
        public var name: String?
        public init(role: String, text: String, reasoning: String? = nil, calls: [Call]? = nil, id: String? = nil, name: String? = nil) {
            self.role = role; self.text = text; self.reasoning = reasoning; self.calls = calls; self.id = id; self.name = name
        }
    }
    public struct Generation: Codable, Sendable, Equatable {
        public var maxTokens: Int?
        public var temperature: Float?
        public var topP: Float?
        public var topK: Int?
        public var presencePenalty: Float?
        public init(maxTokens: Int? = nil, temperature: Float? = nil, topP: Float? = nil, topK: Int? = nil, presencePenalty: Float? = nil) {
            self.maxTokens = maxTokens; self.temperature = temperature; self.topP = topP; self.topK = topK; self.presencePenalty = presencePenalty
        }
    }
    public struct Request: Codable, Sendable {
        public var version: Int
        public var model: String
        public var sessionID: String
        public var system: String
        public var messages: [Message]
        public var tools: [Tool]
        public var generation: Generation
        public init(model: String, sessionID: String = "default", system: String, messages: [Message], tools: [Tool], generation: Generation = .init()) {
            version = 1; self.model = model; self.sessionID = sessionID; self.system = system
            self.messages = messages; self.tools = tools; self.generation = generation
        }
    }
    public struct Usage: Codable, Sendable {
        public var promptTokens = 0
        public var promptSeconds = 0.0
        public var outputTokens = 0
        public var outputSeconds = 0.0
        public init() {}
    }
    public struct Reply: Codable, Sendable {
        public var text = ""
        public var reasoning = ""
        public var calls: [Call] = []
        public var usage = Usage()
        public var truncated = false
        public init() {}
    }
}

/// Inference only: applications own tools, storage, permissions and approvals.
public protocol ModelProvider: Sendable {
    func respond(to request: Inference.Request, onText: @escaping @Sendable (String) -> Void) async throws -> Inference.Reply
}

public enum ModelJSON: Codable, Sendable, Equatable {
    case null, bool(Bool), int(Int), double(Double), string(String), array([Self]), object([String: Self])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([Self].self) { self = .array(v) }
        else { self = .object(try c.decode([String: Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}
