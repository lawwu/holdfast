import Foundation

public enum ServerKind: String, Codable, Sendable, CaseIterable {
    case ollama, lmStudio, custom
    public var defaultURL: String {
        switch self {
        case .ollama: return "http://localhost:11434"
        case .lmStudio: return "http://localhost:1234/v1"
        case .custom: return "http://localhost:8080/v1"
        }
    }
}

/// Non-secret, app-independent connection settings. Credentials are supplied separately.
public struct ServerConfiguration: Codable, Sendable, Equatable {
    public var kind: ServerKind
    public var baseURL: String
    public var model: String
    public var contextWindow: Int
    public init(kind: ServerKind, baseURL: String? = nil, model: String = "", contextWindow: Int = 32768) {
        self.kind = kind; self.baseURL = baseURL ?? kind.defaultURL
        self.model = model; self.contextWindow = contextWindow
    }

    /// A root gets /v1 (or /api). An explicit path is an API base, including proxy prefixes.
    public func endpoint(_ resource: String) throws -> URL {
        guard var c = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(c.scheme?.lowercased() ?? ""), let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil else {
            throw Inference.Failure("Enter an http:// or https:// server address without credentials, query or fragment.")
        }
        var path = c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if kind == .ollama {
            if path.isEmpty { path = "api" }
            else if !path.hasSuffix("/api") && path != "api" { path += "/api" }
        } else if path.isEmpty { path = "v1" }
        c.path = "/" + path + "/" + resource
        guard let url = c.url else { throw Inference.Failure("Invalid model server address.") }
        return url
    }
}

private final class NoModelRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Ollama native API and OpenAI-compatible chat completions. No tool execution or file access.
public final class HTTPModelProvider: ModelProvider, @unchecked Sendable {
    public let configuration: ServerConfiguration
    private let apiKey: String?
    private let thinking: Bool
    private let session: URLSession
    public init(configuration: ServerConfiguration, apiKey: String? = nil, thinking: Bool = false) throws {
        _ = try configuration.endpoint("models")
        guard (4096...1_048_576).contains(configuration.contextWindow) else {
            throw Inference.Failure("Context window must be between 4096 and 1048576 tokens.")
        }
        guard apiKey?.contains(where: { $0.isNewline }) != true else { throw Inference.Failure("Invalid API key.") }
        self.configuration = configuration; self.apiKey = apiKey; self.thinking = thinking
        let settings = URLSessionConfiguration.ephemeral
        settings.urlCache = nil; settings.httpCookieStorage = nil; settings.urlCredentialStorage = nil
        settings.timeoutIntervalForRequest = 300; settings.timeoutIntervalForResource = 1800
        session = URLSession(configuration: settings, delegate: NoModelRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    private func request(_ resource: String, body: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: try configuration.endpoint(resource))
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } else { request.timeoutInterval = 15 }
        return request
    }

    private func check(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else { throw Inference.Failure("Invalid model server response.") }
        guard (200..<300).contains(response.statusCode) else {
            let hint: String
            switch response.statusCode {
            case 300..<400: hint = "Redirects are refused. Use the server's final API address."
            case 401, 403: hint = "Check the server API key."
            case 404: hint = "Check the API base address and model ID."
            default: hint = "Check the server and whether the model supports chat and tools."
            }
            throw Inference.Failure("Model server HTTP \(response.statusCode). \(hint)")
        }
    }

    public func models() async throws -> [String] {
        let (data, response) = try await session.data(for: request(configuration.kind == .ollama ? "tags" : "models"))
        try check(response); try Task.checkCancellation()
        let json = try Self.object(data)
        let key = configuration.kind == .ollama ? "models" : "data"
        guard let entries = json[key] as? [[String: Any]] else { throw Inference.Failure("The server did not return a model list. You can enter a model ID manually.") }
        return Array(Set(entries.compactMap { ($0[configuration.kind == .ollama ? "name" : "id"] as? String) })).sorted()
    }

    public func respond(to input: Inference.Request, onText: @escaping @Sendable (String) -> Void) async throws -> Inference.Reply {
        try Task.checkCancellation()
        guard input.version == 1, !input.model.isEmpty, input.model == configuration.model else { throw Inference.Failure("Select a model ID in Answer settings.") }
        let ollama = configuration.kind == .ollama
        var messages: [[String: Any]] = [["role": "system", "content": input.system]]
        for m in input.messages {
            guard ["user", "assistant", "tool"].contains(m.role) else { throw Inference.Failure("Unsupported message role.") }
            var v: [String: Any] = ["role": m.role, "content": m.text]
            if let reasoning = m.reasoning, !reasoning.isEmpty { v[ollama ? "thinking" : "reasoning_content"] = reasoning }
            if let calls = m.calls, !calls.isEmpty {
                v["tool_calls"] = try calls.map { call -> [String: Any] in
                    let args = try Self.object(Data(call.arguments.utf8))
                    return ["id": call.id, "type": "function", "function": ["name": call.name, "arguments": ollama ? args : call.arguments] as [String: Any]]
                }
            }
            if m.role == "tool" {
                guard let id = m.id, let name = m.name else { throw Inference.Failure("Tool result is missing its call identity.") }
                v["tool_call_id"] = id
                if ollama { v["tool_name"] = name }
            }
            messages.append(v)
        }
        var body: [String: Any] = ["model": input.model, "messages": messages, "stream": true]
        if !input.tools.isEmpty {
            body["tools"] = try input.tools.map { tool in
                ["type": "function", "function": ["name": tool.name, "description": tool.description,
                    "parameters": try JSONSerialization.jsonObject(with: JSONEncoder().encode(tool.parameters))]] as [String: Any]
            }
        }
        let g = input.generation
        if ollama {
            var options: [String: Any] = ["num_ctx": configuration.contextWindow, "num_predict": g.maxTokens ?? 2000]
            if let v = g.temperature { options["temperature"] = v }
            if let v = g.topP { options["top_p"] = v }
            if let v = g.topK { options["top_k"] = v }
            if let v = g.presencePenalty { options["presence_penalty"] = v }
            body["options"] = options; body["think"] = thinking
        } else {
            body["max_tokens"] = g.maxTokens ?? 2000
            if let v = g.temperature { body["temperature"] = v }
            if let v = g.topP { body["top_p"] = v }
            if let v = g.presencePenalty { body["presence_penalty"] = v }
            // Portable chat-completions fields only; reasoning controls vary by server/model.
        }
        let started = Date()
        let (bytes, response) = try await session.bytes(for: request(ollama ? "chat" : "chat/completions", body: body))
        try check(response)
        let jsonResponse = !ollama && (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.contains("application/json") == true
        var parser = ResponseParser(ollama: ollama)
        var line = Data(), event: [String] = [], count = 0
        func consume(_ data: Data) throws {
            guard var text = String(data: data, encoding: .utf8) else { throw Inference.Failure("Invalid UTF-8 from model server.") }
            if text.hasSuffix("\r") { text.removeLast() }
            if ollama { if !text.isEmpty { try parser.accept(Data(text.utf8), onText: onText) }; return }
            if text.isEmpty {
                if !event.isEmpty {
                    let payload = event.joined(separator: "\n"); event = []
                    if payload == "[DONE]" { parser.sawEnd = true }
                    else { try parser.accept(Data(payload.utf8), onText: onText) }
                }
            } else if text.hasPrefix("data:") {
                var value = String(text.dropFirst(5)); if value.hasPrefix(" ") { value.removeFirst() }; event.append(value)
            }
        }
        for try await byte in bytes {
            try Task.checkCancellation()
            count += 1
            guard count <= 32 * 1024 * 1024 else { throw Inference.Failure("Model response exceeded 32 MB.") }
            if byte == 10 && !jsonResponse { try consume(line); line.removeAll(keepingCapacity: true) }
            else { line.append(byte) }
        }
        try Task.checkCancellation()
        if jsonResponse { try parser.accept(line, onText: onText) }
        else {
            if !line.isEmpty { try consume(line) }
            if !event.isEmpty { try consume(Data()) }
        }
        return try parser.finish(seconds: Date().timeIntervalSince(started))
    }

    fileprivate static func object(_ data: Data) throws -> [String: Any] {
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Inference.Failure("Expected a JSON object from the model server.") }
        return value
    }
}

private struct ResponseParser {
    var ollama: Bool
    var reply = Inference.Reply()
    var calls: [Int: Inference.Call] = [:]
    var finished = false
    var sawEnd = false

    mutating func accept(_ data: Data, onText: @Sendable (String) -> Void) throws {
        let json = try HTTPModelProvider.object(data)
        guard json["error"] == nil else { throw Inference.Failure("The model server reported a generation error. Check its model and tool support.") }
        guard !sawEnd else { throw Inference.Failure("Unexpected data after the end of the model response.") }
        let message: [String: Any]
        let streaming: Bool
        if ollama {
            message = json["message"] as? [String: Any] ?? [:]; streaming = false
            if json["done"] as? Bool == true {
                finished = true
                reply.truncated = json["done_reason"] as? String == "length"
                reply.usage.promptTokens = json["prompt_eval_count"] as? Int ?? 0
                reply.usage.outputTokens = json["eval_count"] as? Int ?? 0
                reply.usage.promptSeconds = (json["prompt_eval_duration"] as? Double ?? 0) / 1e9
            }
        } else {
            if let usage = json["usage"] as? [String: Any] {
                reply.usage.promptTokens = usage["prompt_tokens"] as? Int ?? 0
                reply.usage.outputTokens = usage["completion_tokens"] as? Int ?? 0
            }
            guard let choice = (json["choices"] as? [[String: Any]])?.first else { return }
            streaming = choice["delta"] != nil
            message = (choice[streaming ? "delta" : "message"] as? [String: Any]) ?? [:]
            if let reason = choice["finish_reason"] as? String {
                finished = true; reply.truncated = reason == "length"
                guard ["stop", "tool_calls", "length"].contains(reason) else { throw Inference.Failure("Model response ended with \(reason).") }
            }
        }
        let text = message["content"] as? String ?? ""
        reply.text += text; if !text.isEmpty { onText(text) }
        reply.reasoning += (message["thinking"] ?? message["reasoning_content"] ?? message["reasoning"]) as? String ?? ""
        for (position, value) in ((message["tool_calls"] as? [[String: Any]]) ?? []).enumerated() {
            guard let f = value["function"] as? [String: Any] else { throw Inference.Failure("Invalid tool call from model server.") }
            let index = value["index"] as? Int ?? f["index"] as? Int ?? position
            guard (0..<128).contains(index) else { throw Inference.Failure("Invalid tool call index.") }
            var call = calls[index] ?? .init(id: UUID().uuidString, name: "", arguments: "")
            if let id = value["id"] as? String, !id.isEmpty { call.id = id }
            if let name = f["name"] as? String { call.name = streaming ? call.name + name : name }
            if ollama {
                guard let args = f["arguments"] as? [String: Any] else { throw Inference.Failure("Ollama returned invalid tool arguments.") }
                call.arguments = String(decoding: try JSONSerialization.data(withJSONObject: args, options: .sortedKeys), as: UTF8.self)
            } else if let args = f["arguments"] as? String { call.arguments = streaming ? call.arguments + args : args }
            calls[index] = call
        }
    }

    mutating func finish(seconds: Double) throws -> Inference.Reply {
        guard finished else { throw Inference.Failure("The model stream ended before completion. No tool calls were accepted.") }
        guard !reply.truncated || calls.isEmpty else { throw Inference.Failure("The model ran out of tokens during a tool call. No tool calls were accepted.") }
        reply.calls = try calls.keys.sorted().map { index in
            let call = calls[index]!
            guard !call.name.isEmpty, !call.id.isEmpty else { throw Inference.Failure("Incomplete tool call from model server.") }
            _ = try HTTPModelProvider.object(Data(call.arguments.utf8))
            return call
        }
        guard Set(reply.calls.map(\.id)).count == reply.calls.count else { throw Inference.Failure("Duplicate tool call IDs from model server.") }
        reply.usage.outputSeconds = max(0, seconds - reply.usage.promptSeconds)
        return reply
    }
}
