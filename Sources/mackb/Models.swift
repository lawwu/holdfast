import Foundation
import MLX
import MLXEmbedders
import MLXLLM
import MLXHuggingFace
import MLXLMCommon
import Tokenizers

// MARK: - Embeddings: Qwen3-Embedding-0.6B in-process via MLX Swift

final class Embedder: @unchecked Sendable {
    let container: EmbedderModelContainer
    let eosId: Int?

    static func load() async throws -> Embedder? {
        guard let dir = Config.embedModelDir else {
            log("no Qwen3-Embedding-0.6B in the HF cache; keyword search only")
            return nil
        }
        let c = try await EmbedderModelFactory.shared.loadContainer(from: dir, using: #huggingFaceTokenizerLoader())
        let tok = await c.tokenizer
        return Embedder(container: c, eosId: tok.convertTokenToId("<|endoftext|>"))
    }

    private init(container: EmbedderModelContainer, eosId: Int?) {
        self.container = container
        self.eosId = eosId
    }

    /// Qwen3-Embedding: instruction on queries only, EOS appended, last-token
    /// pooling, L2-normalised. One text at a time avoids padding subtleties.
    func embed(_ texts: [String], query: Bool) async throws -> [[Float]] {
        let eos = eosId
        let inputs = texts.map { query ? "Instruct: \(Config.queryInstruction)\nQuery: \($0)" : $0 }
        return await container.perform { ctx -> [[Float]] in
            let pool = Pooling(strategy: .last)
            var out: [[Float]] = []
            for t in inputs {
                var ids = Array(ctx.tokenizer.encode(text: t, addSpecialTokens: true).prefix(1024))
                if let eos, ids.last != eos { ids.append(eos) }
                let x = MLXArray(ids).expandedDimensions(axis: 0)
                let mask = MLXArray.ones([1, ids.count]).asType(.bool)
                let h = ctx.model(x, positionIds: nil, tokenTypeIds: nil, attentionMask: mask)
                let v = pool(h, mask: mask, normalize: true)
                v.eval()
                out.append(v[0].asArray(Float.self))
            }
            return out
        }
    }
}

// MARK: - LLM backend

protocol LLMBackend {
    /// Streams the answer to `onToken`; returns generation stats.
    func chat(system: String, user: String, onToken: @escaping @Sendable (String) -> Void) async throws -> GenStats
}

struct GenStats {
    var promptTokens: Int
    var promptSeconds: Double
    var outputTokens: Int
    var outputSeconds: Double
    var tokPerSec: Double { Double(outputTokens) / max(outputSeconds, 0.001) }
    var promptTokPerSec: Double { Double(promptTokens) / max(promptSeconds, 0.001) }
}

/// Ollama's native /api/chat (needed for `think: false`, which Qwen 3.8 needs:
/// its default reasoning effort turns a 2-minute answer into 20).
struct OllamaBackend: LLMBackend {
    var model = Config.llmModel

    func chat(system: String, user: String, onToken: @escaping @Sendable (String) -> Void) async throws -> GenStats {
        var req = URLRequest(url: Config.ollamaURL.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.timeoutInterval = 1800
        let body: [String: Any] = [
            "model": model, "stream": true, "think": false, "keep_alive": "30m",
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "options": ["temperature": Config.temperature, "top_p": Config.topP, "top_k": Config.topK,
                        "presence_penalty": Config.presencePenalty, "num_ctx": 16384],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, resp) = try await URLSession.shared.bytes(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw MacKBError("Ollama returned \((resp as? HTTPURLResponse)?.statusCode ?? 0); is `ollama serve` running and \(model) installed?")
        }
        var stats = GenStats(promptTokens: 0, promptSeconds: 0, outputTokens: 0, outputSeconds: 0)
        for try await line in bytes.lines {
            guard let d = line.data(using: .utf8), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            if let e = j["error"] as? String { throw MacKBError("Ollama: \(e)") }
            if let m = j["message"] as? [String: Any], let c = m["content"] as? String, !c.isEmpty { onToken(c) }
            if j["done"] as? Bool == true {
                stats.promptTokens = j["prompt_eval_count"] as? Int ?? 0
                stats.promptSeconds = Double(j["prompt_eval_duration"] as? Int ?? 0) / 1e9
                stats.outputTokens = j["eval_count"] as? Int ?? 0
                stats.outputSeconds = Double(j["eval_duration"] as? Int ?? 0) / 1e9
            }
        }
        return stats
    }
}

// MARK: - MLX backend: Qwen 3.8 27B 4-bit in-process (no Ollama)

/// Pick the backend: MACKB_BACKEND=mlx loads the model inside this process.
func makeBackend() async throws -> LLMBackend {
    if (ProcessInfo.processInfo.environment["MACKB_BACKEND"] ?? "ollama") == "mlx" { return try await MLXBackend.shared() }
    return OllamaBackend()
}

final class MLXBackend: LLMBackend, @unchecked Sendable {
    let container: ModelContainer
    let loadSeconds: Double
    nonisolated(unsafe) private static var cached: MLXBackend?

    /// Default: mlx-community/Qwen3.8-27B-4bit from the HF cache. Override with MACKB_MLX_DIR.
    static var modelDir: URL? {
        if let p = ProcessInfo.processInfo.environment["MACKB_MLX_DIR"] { return URL(fileURLWithPath: p) }
        let repo = ProcessInfo.processInfo.environment["MACKB_MLX_REPO"] ?? "mlx-community/Qwen3.8-27B-4bit"
        let snaps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models--\(repo.replacingOccurrences(of: "/", with: "--"))/snapshots")
        guard let s = try? FileManager.default.contentsOfDirectory(atPath: snaps.path).sorted().last else { return nil }
        return snaps.appendingPathComponent(s)
    }

    static func shared() async throws -> MLXBackend {
        if let c = cached { return c }
        guard let dir = modelDir else { throw MacKBError("MLX model not found in the HF cache") }
        let t0 = Date()
        log("loading \(dir.path.components(separatedBy: "models--").last ?? "") with MLX…")
        let c = try await LLMModelFactory.shared.loadContainer(from: dir, using: #huggingFaceTokenizerLoader())
        let b = MLXBackend(container: c, loadSeconds: Date().timeIntervalSince(t0))
        log(String(format: "loaded in %.1fs", b.loadSeconds))
        cached = b
        return b
    }

    private init(container: ModelContainer, loadSeconds: Double) {
        self.container = container
        self.loadSeconds = loadSeconds
    }

    func chat(system: String, user: String, onToken: @escaping @Sendable (String) -> Void) async throws -> GenStats {
        let params = GenerateParameters(maxTokens: 2000, temperature: Float(Config.temperature), topP: Float(Config.topP),
                                        topK: Config.topK, presencePenalty: Float(Config.presencePenalty))
        let (text, info) = try await container.perform { (context: ModelContext) -> (String, GenerateCompletionInfo?) in
            let input = try await context.processor.prepare(
                input: UserInput(chat: [.system(system), .user(user)], additionalContext: ["enable_thinking": false]))
            var text = ""
            var info: GenerateCompletionInfo?
            for await g in try generate(input: input, parameters: params, context: context) {
                switch g {
                case .chunk(let s):
                    text += s
                    onToken(s)  // stream to the caller as tokens arrive
                case .info(let i): info = i
                default: break
                }
            }
            return (text, info)
        }
        return GenStats(promptTokens: info?.promptTokenCount ?? 0, promptSeconds: info?.promptTime ?? 0,
                        outputTokens: info?.generationTokenCount ?? 0, outputSeconds: info?.generateTime ?? 0)
    }
}
