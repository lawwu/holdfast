import Foundation
import MLX
import MLXEmbedders
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
    func chat(system: String, user: String, onToken: (String) -> Void) async throws -> GenStats
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

    func chat(system: String, user: String, onToken: (String) -> Void) async throws -> GenStats {
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
