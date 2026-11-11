import Foundation
import Security
import ModelProviders

/// Holdfast owns persistence and credentials. ModelProviders has no app preferences or vault access.
enum ProviderSettings {
    static var selected: Backend {
        let env = ProcessInfo.processInfo.environment["HOLDFAST_BACKEND"]
        switch env {
        case "mlx": return .mlx
        case "ollama": return .ollama
        case "lmstudio", "lmStudio": return .lmStudio
        case "custom", "remote": return .remote
        default: return UserDefaults.standard.string(forKey: "backend").flatMap(Backend.init(rawValue:)) ?? .mlx
        }
    }
    static func saved(_ kind: ServerKind) -> ServerConfiguration {
        if let data = UserDefaults.standard.data(forKey: "modelServer.\(kind.rawValue)"),
           let c = try? JSONDecoder().decode(ServerConfiguration.self, from: data), c.kind == kind { return c }
        // Preserve existing installations' server choices without persisting credentials.
        if kind == .custom {
            return .init(kind: kind, baseURL: UserDefaults.standard.string(forKey: "remoteURL") ?? kind.defaultURL,
                         model: UserDefaults.standard.string(forKey: "remoteModel") ?? "")
        }
        return .init(kind: kind, model: kind == .ollama ? Config.llmModel : "")
    }
    static func current(_ kind: ServerKind) -> ServerConfiguration {
        var c = saved(kind)
        let env = ProcessInfo.processInfo.environment
        let legacyURL = kind == .ollama ? env["HOLDFAST_OLLAMA"] : kind == .custom ? env["HOLDFAST_REMOTE_URL"] : nil
        let legacyModel = kind == .ollama ? env["HOLDFAST_LLM"] : kind == .custom ? env["HOLDFAST_REMOTE_MODEL"] : nil
        c.baseURL = env["HOLDFAST_PROVIDER_URL"] ?? legacyURL ?? c.baseURL
        c.model = env["HOLDFAST_PROVIDER_MODEL"] ?? legacyModel ?? c.model
        if let raw = env["HOLDFAST_CONTEXT_WINDOW"], let n = Int(raw) { c.contextWindow = n }
        return c
    }
    static func credential(_ c: ServerConfiguration) throws -> String? {
        if let key = ProcessInfo.processInfo.environment["HOLDFAST_PROVIDER_API_KEY"] { return key }
        return try ProviderCredential.read(endpoint: credentialID(c))
    }
    static func credentialID(_ c: ServerConfiguration) -> String {
        // Bind credentials to an endpoint, so editing an address cannot send an old key elsewhere.
        c.kind.rawValue + ":" + ((try? c.endpoint(""))?.absoluteString ?? c.baseURL)
    }
    static func save(_ c: ServerConfiguration, key: String) throws {
        _ = try HTTPModelProvider(configuration: c)
        guard !c.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw HoldfastError("Enter a model ID or choose a discovered model.") }
        guard c.contextWindow >= 16384 else { throw HoldfastError("Holdfast needs a context window of at least 16384 tokens for its agent and conversation history.") }
        try ProviderCredential.write(key.isEmpty ? nil : key, endpoint: credentialID(c))
        UserDefaults.standard.set(try JSONEncoder().encode(c), forKey: "modelServer.\(c.kind.rawValue)")
    }
}

final class ServerBackend: LLMBackend, @unchecked Sendable {
    let configuration: ServerConfiguration
    let provider: HTTPModelProvider
    let profile: ModelProfile
    init(kind: ServerKind) throws {
        var config = ProviderSettings.current(kind)
        var preferences = ModelPreferences.load(config.model, endpoint: config.baseURL)
        preferences.contextTokens = min(preferences.contextTokens, config.contextWindow)
        profile = preferences
        config.contextWindow = preferences.contextTokens
        configuration = config
        guard !configuration.model.isEmpty else { throw HoldfastError("Choose a model in Settings → Answer for this provider.") }
        guard configuration.contextWindow >= 16384 else { throw HoldfastError("Holdfast needs at least 16384 context tokens.") }
        provider = try HTTPModelProvider(configuration: configuration, apiKey: ProviderSettings.credential(configuration), thinking: profile.thinking)
    }
    func chat(system: String, user: String, temperature: Double?, onToken: @escaping @Sendable (String) -> Void) async throws -> GenStats {
        // The caller routes mixed-vault private context before this point. A private
        // vault is also protected here for every plain-chat caller (including filing).
        if Profile.vaultDefault.id == Profile.privateNotes.id {
            ModelPrivacy.keptLocal = true
            return try await MLXBackend.shared().chat(system: system, user: user, temperature: temperature, onToken: onToken)
        }
        var generation = profile.generation
        if let temperature { generation.temperature = Float(temperature) }
        let reply = try await provider.respond(to: .init(model: configuration.model, system: system,
            messages: [.init(role: "user", text: user)], tools: [],
            generation: generation), onText: onToken)
        return .init(promptTokens: reply.usage.promptTokens, promptSeconds: reply.usage.promptSeconds,
                     outputTokens: reply.usage.outputTokens, outputSeconds: reply.usage.outputSeconds)
    }
}

struct ServerAgentModel: AgentRuntime.Model {
    let backend: ServerBackend
    var name: String { backend.configuration.model }
    // Even loopback servers may proxy cloud models. Only embedded LocalMLX qualifies for local-only content.
    let isLocal = false
    func respondNative(_ input: Inference.Request, onText: @escaping @Sendable (String) -> Void) async throws -> AgentRuntime.Reply {
        var input = input; input.generation = backend.profile.generation
        let reply = try await backend.provider.respond(to: input, onText: onText)
        return try JSONDecoder().decode(AgentRuntime.Reply.self, from: JSONEncoder().encode(reply))
    }
    func respond(to request: AgentRuntime.Request, onText: @escaping @Sendable (String) -> Void) async throws -> AgentRuntime.Reply {
        guard !request.localOnly else { throw HoldfastError("Private content must stay in LocalMLX on this Mac.") }
        let messages: [Inference.Message] = request.messages.map {
            switch $0 {
            case .user(let text): return .init(role: "user", text: text)
            case .assistant(let reply): return .init(role: "assistant", text: reply.text, reasoning: reply.reasoning,
                calls: reply.calls.map { .init(id: $0.id, name: $0.name, arguments: $0.arguments) })
            case .tool(let call, let result): return .init(role: "tool", text: result.text, id: call.id, name: call.name)
            }
        }
        return try await respondNative(.init(model: name, system: request.system, messages: messages,
            tools: request.tools.map(MLXAgentModel.tool), generation: .init(maxTokens: 2000,
                temperature: Float(Config.temperature), topP: Float(Config.topP))), onText: onText)
    }
}

func usesModelServer(_ llm: LLMBackend) -> Bool { llm is ServerBackend }

enum ProviderCredential {
    private static func query(_ endpoint: String, service: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: endpoint]
    }
    static func read(endpoint: String) throws -> String? {
        try LegacyCompatibility.readCredential(suffix: "model-servers",
            read: { try readStored(endpoint: endpoint, service: $0) },
            write: { try writeStored($0, endpoint: endpoint, service: $1) })
    }
    private static func readStored(endpoint: String, service: String) throws -> String? {
        var request = query(endpoint, service: service); request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }; try check(status)
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else { throw HoldfastError("Could not read the server API key.") }
        return key
    }
    static func write(_ key: String?, endpoint: String) throws {
        try LegacyCompatibility.writeCredential(key, suffix: "model-servers",
            write: { try writeStored($0, endpoint: endpoint, service: $1) })
    }
    private static func writeStored(_ key: String?, endpoint: String, service: String) throws {
        let request = query(endpoint, service: service)
        guard let key else { let status = SecItemDelete(request as CFDictionary); if status != errSecItemNotFound { try check(status) }; return }
        let attributes = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = request.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            try check(SecItemAdd(item as CFDictionary, nil))
        } else { try check(status) }
    }
    private static func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw HoldfastError("Could not access the server API key in Keychain (\(status)).") }
    }
}
