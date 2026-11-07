import Foundation
import MLXLMCommon

// MARK: - A model on another Mac
//
// Holdfast runs on this Mac (vault, index, embedder, reranker) and sends only
// the prompt (the question, the passages search found, the conversation) to a
// model served by another Mac on the home network or tailnet: LM Studio,
// mlx_lm.server or Ollama, all of which speak the OpenAI chat-completions API.
// Use the other Mac's Tailscale name so the traffic is encrypted end to end.

/// Refuses every redirect: the configured address is the only place a request may go.
final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum Remote {
    static let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)

    /// "http://studio:1234" (LM Studio), "http://studio:8080" (mlx_lm.server), "http://studio:11434" (Ollama).
    static var url: URL? {
        let s = ProcessInfo.processInfo.environment["MACKB_REMOTE_URL"] ?? UserDefaults.standard.string(forKey: "remoteURL") ?? ""
        return URL(string: s.trimmingCharacters(in: .whitespaces)).flatMap { $0.host == nil ? nil : $0 }
    }
    static var model: String {
        ProcessInfo.processInfo.environment["MACKB_REMOTE_MODEL"] ?? UserDefaults.standard.string(forKey: "remoteModel") ?? ""
    }
    /// Seconds to wait for the first byte (a big model loading on the other Mac can take a while).
    static let timeout: TimeInterval = 300

    static func endpoint(_ path: String) -> URL? {
        guard let u = url else { return nil }
        let base = u.path.hasSuffix("/v1") ? u : u.appendingPathComponent("v1")
        return base.appendingPathComponent(path)
    }

    /// The models the server offers.
    static func models(at base: URL) async throws -> [String] {
        let u = (base.path.hasSuffix("/v1") ? base : base.appendingPathComponent("v1")).appendingPathComponent("models")
        var req = URLRequest(url: u)
        req.timeoutInterval = 6
        let (data, resp) = try await Remote.session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["data"] as? [[String: Any]] else { throw MacKBError("no model list at \(u.absoluteString)") }
        return list.compactMap { $0["id"] as? String }.sorted()
    }

    /// Round trip to the server, in milliseconds.
    static func ping(_ base: URL) async throws -> Int {
        let t0 = Date()
        _ = try await models(at: base)
        return Int(Date().timeIntervalSince(t0) * 1000)
    }

    static func request(_ body: [String: Any]) throws -> URLRequest {
        guard let u = endpoint("chat/completions") else { throw MacKBError("no address set for the model on another Mac") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    static var host: String { url?.host ?? "another Mac" }

    /// Errors that mean the other Mac isn't there (asleep, off the network), as opposed to Stop or a bad reply.
    static func isUnreachable(_ e: URLError) -> Bool {
        [.cannotConnectToHost, .cannotFindHost, .timedOut, .networkConnectionLost, .notConnectedToInternet,
         .dnsLookupFailed, .secureConnectionFailed, .appTransportSecurityRequiresSecureConnection].contains(e.code)
    }
    /// Set when a request fell back to this Mac's model; the app shows it, then clears it.
    nonisolated(unsafe) static var fellBack = false
    /// Set when a request was kept on this Mac because it involved counseling notes.
    nonisolated(unsafe) static var keptLocal = false

    /// Counseling material never goes to another Mac: a request that would send any is answered here.
    static func touchesCounseling(_ chunks: [Chunk]) -> Bool { chunks.contains { Profile.isCounseling($0.relPath) } }
}

/// Plain answers and filing through the other Mac's model, streamed.
struct RemoteBackend: LLMBackend {
    var model = Remote.model

    func chat(system: String, user: String, temperature: Double?, onToken: @escaping @Sendable (String) -> Void) async throws -> GenStats {
        let wrote = OutputBuffer()
        do {
            return try await stream(system: system, user: user, temperature: temperature) { t in wrote.append(t); onToken(t) }
        } catch let e as URLError where Remote.isUnreachable(e) && !Task.isCancelled && wrote.text.isEmpty {
            // The other Mac is asleep or off the network, and nothing was written yet: use this Mac's model.
            guard MLXBackend.modelDir(repo: MLXBackend.currentRepo) != nil else {
                throw MacKBError("\(Remote.host) didn't answer, and no model is downloaded on this Mac to answer instead")
            }
            log("\(Remote.host) unreachable (\(e.code.rawValue)); using this Mac's model")
            Remote.fellBack = true
            return try await MLXBackend.shared().chat(system: system, user: user, temperature: temperature, onToken: onToken)
        } catch let e as URLError where e.code == .cancelled || Task.isCancelled {
            return GenStats(promptTokens: 0, promptSeconds: 0, outputTokens: 0, outputSeconds: 0)  // Stop: keep what was written
        } catch let e as URLError {
            throw MacKBError("lost the connection to \(Remote.host)" + (wrote.text.isEmpty ? "" : " partway through the answer") + " (\(e.localizedDescription))")
        }
    }

    private func stream(system: String, user: String, temperature: Double?, onToken: @escaping @Sendable (String) -> Void) async throws -> GenStats {
        let t0 = Date()
        var body: [String: Any] = ["model": model, "stream": true, "max_tokens": 2000,
                                   "temperature": temperature ?? Config.temperature, "top_p": Config.topP,
                                   "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
        if !Thinking.on { body["chat_template_kwargs"] = ["enable_thinking": false] }
        let (bytes, resp) = try await Remote.session.bytes(for: try Remote.request(body))
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw MacKBError("the model on \(Remote.host) returned \((resp as? HTTPURLResponse)?.statusCode ?? 0)")
        }
        var first: Date?
        var tokens = 0
        var inReasoning = false
        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                  let delta = (obj["choices"] as? [[String: Any]])?.first?["delta"] as? [String: Any] else { continue }
            // Servers put reasoning in its own field ("reasoning_content", or Ollama's "reasoning"):
            // wrap it in <think> so it becomes a Thinking step, never part of the answer.
            if let r = (delta["reasoning_content"] ?? delta["reasoning"]) as? String, !r.isEmpty {
                if !inReasoning { onToken("<think>"); inReasoning = true }
                onToken(r)
            }
            if let c = delta["content"] as? String, !c.isEmpty {
                if inReasoning { onToken("</think>"); inReasoning = false }
                if first == nil { first = Date() }
                tokens += 1
                onToken(c)
            }
        }
        let gen = first.map { Date().timeIntervalSince($0) } ?? 0
        return GenStats(promptTokens: 0, promptSeconds: (first ?? Date()).timeIntervalSince(t0), outputTokens: tokens, outputSeconds: gen)
    }
}

/// Research over the network: the same tools as Agent, run on this Mac, with the
/// model's decisions coming from the other Mac (OpenAI tool calls, one round at a time).
enum RemoteAgent {
    static func run(_ question: String, embedder: Embedder?, prior: [(q: String, a: String)] = [],
                    onEvent: @escaping @Sendable (Agent.Event) -> Void) async throws -> Answer {
        do {
            return try await loop(question, embedder: embedder, prior: prior, onEvent: onEvent)
        } catch let e as URLError where Remote.isUnreachable(e) && !Task.isCancelled {
            guard MLXBackend.modelDir(repo: MLXBackend.currentRepo) != nil else {
                throw MacKBError("\(Remote.host) didn't answer, and no model is downloaded on this Mac to research with instead")
            }
            onEvent(.step("\(Remote.host) didn't answer: researching with this Mac's model"))
            onEvent(.resetText)
            Remote.fellBack = true
            return try await Agent.run(question, embedder: embedder, backend: try await MLXBackend.shared(), prior: prior, onEvent: onEvent)
        } catch let e as URLError where e.code == .cancelled || Task.isCancelled {
            return Answer(text: "", sources: [], stats: GenStats(promptTokens: 0, promptSeconds: 0, outputTokens: 0, outputSeconds: 0), retrievalSeconds: 0)
        } catch is KeepLocal {
            guard MLXBackend.modelDir(repo: MLXBackend.currentRepo) != nil else {
                throw MacKBError("this needs counseling notes, which stay on this Mac, and no model is downloaded here")
            }
            onEvent(.step("Counseling notes stay on this Mac: researching here instead"))
            onEvent(.resetText)
            onEvent(.sources([]))
            Remote.keptLocal = true
            return try await Agent.run(question, embedder: embedder, backend: try await MLXBackend.shared(), prior: prior, onEvent: onEvent)
        }
    }

    /// Thrown when a tool returns counseling material: the request moves to this Mac before it is sent.
    struct KeepLocal: Error {}

    private static func loop(_ question: String, embedder: Embedder?, prior: [(q: String, a: String)],
                             onEvent: @escaping @Sendable (Agent.Event) -> Void) async throws -> Answer {
        let t0 = Date()
        let system = [Profile.vaultDefault.systemPrompt, Agent.instructions, todayLine(), Agent.vaultOverview()].joined(separator: "\n\n")
        var messages: [[String: Any]] = [["role": "system", "content": system]]
        for p in prior.suffix(Conversation.turns) {
            messages.append(["role": "user", "content": p.q])
            messages.append(["role": "assistant", "content": String(p.a.prefix(Conversation.answerChars))])
        }
        messages.append(["role": "user", "content": question])
        let tools = toJSON(Agent.tools)
        let ctx = ToolContext(embedder: embedder)
        var final = ""
        var outTokens = 0
        for step in 0...Agent.maxSteps {
            if Task.isCancelled { break }
            var body: [String: Any] = ["model": Remote.model, "stream": false, "max_tokens": 2000,
                                       "temperature": Config.temperature, "messages": messages]
            if step < Agent.maxSteps { body["tools"] = tools } else {
                messages.append(["role": "user", "content": "Answer now from what the tools returned, with [n] citations."])
                body["messages"] = messages
            }
            if !Thinking.on { body["chat_template_kwargs"] = ["enable_thinking": false] }
            let (data, resp) = try await Remote.session.data(for: try Remote.request(body))
            guard (resp as? HTTPURLResponse)?.statusCode == 200,
                  let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let msg = (obj["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any] else {
                throw MacKBError("the model on \(Remote.host) sent an unexpected reply: \(String(decoding: data.prefix(200), as: UTF8.self))")
            }
            outTokens += ((obj["usage"] as? [String: Any])?["completion_tokens"] as? Int) ?? 0
            let text = (msg["content"] as? String) ?? ""
            let reasoning = (msg["reasoning_content"] as? String) ?? ""
            let (thought, said) = Thinking.split(text)
            let allThought = [reasoning, thought].filter { !$0.isEmpty }.joined(separator: "\n\n")
            if !allThought.isEmpty, Thinking.on { onEvent(.step("Thinking" + Steps.sep + allThought)) }
            let calls = (msg["tool_calls"] as? [[String: Any]]) ?? []
            if calls.isEmpty || step == Agent.maxSteps {
                final = said
                onEvent(.token(said))
                break
            }
            messages.append(["role": "assistant", "content": text, "tool_calls": calls])
            for (k, c) in calls.enumerated() {
                let fn = c["function"] as? [String: Any] ?? [:]
                let name = fn["name"] as? String ?? ""
                let argText = fn["arguments"] as? String ?? "{}"
                let args = (try? JSONSerialization.jsonObject(with: Data(argText.utf8)) as? [String: Any]) ?? [:]
                let call = ToolCall(function: .init(name: name, arguments: args.mapValues { "\($0)" as any Sendable }))
                let result = await ctx.call(call) { onEvent(.step($0)) }
                if Remote.touchesCounseling(ctx.sources) || (name == "read_note" && Profile.isCounseling(argText)) { throw KeepLocal() }
                var detail = "\(name)(\(argText))\n\n" + String(result.prefix(Steps.resultChars)) + (result.count > Steps.resultChars ? "\n[…]" : "")
                let preamble = stripThoughts(said).trimmingCharacters(in: .whitespacesAndNewlines)
                if k == 0, !preamble.isEmpty { detail = "Model: \(preamble)\n\n" + detail }
                onEvent(.stepDetail(detail))
                onEvent(.sources(ctx.sources))
                messages.append(["role": "tool", "tool_call_id": c["id"] as? String ?? "call_\(step)_\(k)", "content": result])
            }
        }
        final = stripThoughts(final)
        let cited = (try? NSRegularExpression(pattern: #"\[(\d+)\]"#))?
            .matches(in: final, range: NSRange(final.startIndex..., in: final))
            .compactMap { Range($0.range(at: 1), in: final).flatMap { Int(final[$0]) } } ?? []
        var bad = Array(Set(cited.filter { $0 < 1 || $0 > ctx.sources.count })).sorted()
        if ctx.sources.isEmpty { final = final.replacingOccurrences(of: #"\s?\[\d+\]"#, with: "", options: .regularExpression); bad = [] }
        let secs = Date().timeIntervalSince(t0)
        return Answer(text: final, badCitations: bad, sources: ctx.sources,
                      stats: GenStats(promptTokens: 0, promptSeconds: 0, outputTokens: outTokens, outputSeconds: secs),
                      retrievalSeconds: secs, steps: ctx.log)
    }

    /// ToolSpec ([String: any Sendable]) as plain JSON objects.
    static func toJSON(_ specs: [ToolSpec]) -> [Any] {
        func plain(_ v: Any) -> Any {
            if let d = v as? [String: any Sendable] { return d.mapValues { plain($0) } }
            if let d = v as? [String: Any] { return d.mapValues { plain($0) } }
            if let a = v as? [any Sendable] { return a.map { plain($0) } }
            if let a = v as? [Any] { return a.map { plain($0) } }
            return v
        }
        return specs.map { plain($0) }
    }
}
