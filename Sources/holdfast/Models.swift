import Foundation
import Metal
import MLX
import MLXEmbedders
import MLXLLM
import MLXRerankers
import MLXHuggingFace
import MLXLMCommon
import Tokenizers
import LocalMLX

// MARK: - Embeddings: Qwen3-Embedding-0.6B in-process via MLX Swift

final class Embedder: @unchecked Sendable {
    let container: EmbedderModelContainer
    let eosId: Int?
    let spec: EmbedSpec

    static var isEnabled: Bool {
        Prefs.searchByMeaning && ProcessInfo.processInfo.environment["HOLDFAST_EMBED"] != "none"
    }

    /// After the app drops its reference, return unused MLX buffers to the system.
    static func clearUnusedMemory() { Memory.clearCache() }

    static func load() async throws -> Embedder? {
        let spec = Config.embedSpec
        // HOLDFAST_EMBED=none: keyword search only (to measure what embeddings add).
        guard isEnabled else { return nil }
        guard let dir = Config.embedModelDir else {
            log("no downloaded \(spec.label); keyword search only")
            return nil
        }
        let c = try await EmbedderModelFactory.shared.loadContainer(from: dir, using: #huggingFaceTokenizerLoader())
        let tok = await c.tokenizer
        return Embedder(container: c, eosId: spec == .qwen3 ? tok.convertTokenToId("<|endoftext|>") : nil, spec: spec)
    }

    private init(container: EmbedderModelContainer, eosId: Int?, spec: EmbedSpec) {
        self.container = container
        self.eosId = eosId
        self.spec = spec
    }

    /// Qwen3-Embedding: instruction on queries only, EOS appended, last-token
    /// pooling, L2-normalised. One text at a time avoids padding subtleties.
    /// EmbeddingGemma: its own task prompts, and the model pools (mean, then dense
    /// layers) and normalises itself.
    func embed(_ texts: [String], query: Bool) async throws -> [[Float]] {
        let eos = eosId
        let inputs: [String]
        switch spec {
        case .qwen3: inputs = texts.map { query ? "Instruct: \(Config.queryInstruction)\nQuery: \($0)" : $0 }
        case .embeddingGemma: inputs = texts.map { query ? "task: search result | query: \($0)" : "title: none | text: \($0)" }
        }
        let strategy: Pooling.Strategy = spec == .qwen3 ? .last : .none
        return await container.perform { ctx -> [[Float]] in
            let pool = Pooling(strategy: strategy)
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

// MARK: - Reranker: Qwen3-Reranker-0.6B 4-bit in-process (oss-best-practices.md #1)

final class Reranker: @unchecked Sendable {
    let container: RerankerContainer
    nonisolated(unsafe) private static var cached: Reranker?
    nonisolated(unsafe) private static var tried = false

    // Instruction-aware reranking adds a few points for Qwen3-Reranker; the
    // instruction comes from the vault's profile (Profile.swift).

    /// Which reranker: HOLDFAST_RERANK_REPO (e.g. mlx-community/Qwen3-Reranker-4B-mxfp8), else 0.6B 4-bit.
    static var repo: String {
        ProcessInfo.processInfo.environment["HOLDFAST_RERANK_REPO"] ?? "mlx-community/Qwen3-Reranker-0.6B-4bit"
    }
    /// Short name for reports, e.g. "Qwen3-Reranker-4B".
    static var label: String {
        (repo.components(separatedBy: "/").last ?? repo).replacingOccurrences(of: #"-(4bit|8bit|mxfp8|bf16)$"#, with: "", options: .regularExpression)
    }

    static var modelDir: URL? {
        if let p = ProcessInfo.processInfo.environment["HOLDFAST_RERANK_DIR"] { return URL(fileURLWithPath: p) }
        return ModelFiles.directory(repo: repo, modelsDirectory: Prefs.modelsDir)
    }

    /// Loaded once; nil (keyword + vector only) if missing or HOLDFAST_RERANK=0.
    static func shared() async -> Reranker? {
        guard Prefs.rerankerOn else { return nil }
        if tried { return cached }
        guard ProcessInfo.processInfo.environment["HOLDFAST_RERANK"] != "0", let dir = modelDir else { return nil }
        tried = true
        do {
            let c = try await RerankerModelFactory.shared.loadContainer(
                from: dir, using: #huggingFaceTokenizerLoader(), allowUnverifiedModel: true)
            cached = Reranker(container: c)
        } catch {
            log("reranker unavailable: \(error)")
        }
        return cached
    }

    private init(container: RerankerContainer) { self.container = container }

    /// Relevance 0…1 for each document, in the order given.
    func score(query: String, documents: [String]) async throws -> [Double] {
        guard !documents.isEmpty else { return [] }
        let r = try await container.scores(query: query, documents: documents, instruction: Profile.vaultDefault.rerankInstruction)
        var out = Array(repeating: 0.0, count: documents.count)
        for x in r.results where x.index < out.count { out[x.index] = x.score }
        return out
    }
}

/// Several models share unified memory (27B LLM, embedder, reranker, Parakeet):
/// cap MLX's buffer cache so freed memory goes back to the system.
func configureMLXMemory() {
    // HTTP providers and scripted tool tests can run on Macs without a Metal device.
    // Setting MLX's cache limit would otherwise initialize the unavailable GPU.
    guard MTLCreateSystemDefaultDevice() != nil else { return }
    Memory.cacheLimit = 2 << 30  // 2 GB
}

// MARK: - LLM backend

protocol LLMBackend {
    /// Streams the answer to `onToken`; returns generation stats. `temperature`
    /// overrides `Config.temperature` (filing wants exact JSON, so it runs cooler).
    func chat(system: String, user: String, temperature: Double?, onToken: @escaping @Sendable (String) -> Void) async throws -> GenStats
}

extension LLMBackend {
    func chat(system: String, user: String, onToken: @escaping @Sendable (String) -> Void) async throws -> GenStats {
        try await chat(system: system, user: user, temperature: nil, onToken: onToken)
    }
}

struct GenStats {
    var promptTokens: Int
    var promptSeconds: Double
    var outputTokens: Int
    var outputSeconds: Double
    var tokPerSec: Double { Double(outputTokens) / max(outputSeconds, 0.001) }
    var promptTokPerSec: Double { Double(promptTokens) / max(promptSeconds, 0.001) }
}

func makeBackend() async throws -> LLMBackend {
    if ProcessInfo.processInfo.environment["HOLDFAST_BACKEND"] == "gemini" { return try GeminiBackend() }
    if let kind = ProviderSettings.selected.serverKind { return try ServerBackend(kind: kind) }
    return try await MLXBackend.shared()
}

/// Google's Gemini API, for evals on synthetic data only: the app never offers
/// it, because anything sent here leaves the Mac. Needs GEMINI_API_KEY;
/// HOLDFAST_GEMINI_MODEL picks the model.
struct GeminiBackend: LLMBackend {
    var model = ProcessInfo.processInfo.environment["HOLDFAST_GEMINI_MODEL"] ?? "gemini-flash-latest"
    let key: String

    init() throws {
        guard let k = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !k.isEmpty else {
            throw HoldfastError("set GEMINI_API_KEY to use the Gemini backend")
        }
        key = k
    }

    func chat(system: String, user: String, temperature: Double?, onToken: @escaping @Sendable (String) -> Void) async throws -> GenStats {
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": user]]]],
            "generationConfig": ["temperature": temperature ?? Config.temperature, "topP": Config.topP, "maxOutputTokens": 4000],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let t0 = Date()
        let (data, resp) = try await URLSession.shared.data(for: req)
        let secs = Date().timeIntervalSince(t0)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HoldfastError("Gemini returned \((resp as? HTTPURLResponse)?.statusCode ?? 0): \(String(data: data, encoding: .utf8)?.prefix(300) ?? "")")
        }
        let parts = ((j["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        let text = parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
        onToken(text)
        let usage = j["usageMetadata"] as? [String: Any]
        return GenStats(promptTokens: usage?["promptTokenCount"] as? Int ?? 0, promptSeconds: 0,
                        outputTokens: usage?["candidatesTokenCount"] as? Int ?? 0, outputSeconds: secs)
    }
}

final class MLXBackend: LLMBackend, @unchecked Sendable {
    let container: ModelContainer
    let loadSeconds: Double
    nonisolated(unsafe) private static var cached: MLXBackend?

    /// Which repo to run: HOLDFAST_MLX_REPO, else the Settings choice.
    static var currentRepo: String { ProcessInfo.processInfo.environment["HOLDFAST_MLX_REPO"] ?? Prefs.mlxRepo }
    nonisolated(unsafe) private(set) static var loadedRepo: String?

    /// HOLDFAST_MLX_DIR wins; then the Hugging Face cache; then the app's own downloads.
    static func modelDir(repo: String = currentRepo) -> URL? {
        if let p = ProcessInfo.processInfo.environment["HOLDFAST_MLX_DIR"] { return URL(fileURLWithPath: p) }
        if let custom = CustomLocalModels.find(repo) {
            let validate: (URL) -> Bool = { directory in
                (try? LocalModelFiles.inspect(directory: directory).modelType) == custom.modelType
            }
            if let folder = custom.folder { return validate(folder) ? folder : nil }
            return ModelFiles.directory(repo: custom.location, modelsDirectory: Prefs.modelsDir, validate: validate)
        }
        return ModelFiles.directory(repo: repo, modelsDirectory: Prefs.modelsDir)
    }

    static var isLoaded: Bool { cached != nil }

    /// Drop the model so its memory can be reclaimed (reloads on next use).
    static func unload() {
        cached = nil
        loadedRepo = nil
        Memory.clearCache()
    }

    /// Download an MLX repo into the app's models folder. `progress` gets 0…1.
    static func download(repo: String, progress: @escaping @Sendable (ModelDownloadProgress) async -> Void) async throws {
        let source = try ModelDownloadSource.current()
        try await ModelDownloader.download(repo: repo, source: source, to: Prefs.modelsDir, progress: progress)
    }

    static func shared() async throws -> MLXBackend {
        let repo = currentRepo
        if let c = cached, loadedRepo == repo { return c }
        if cached != nil { unload() }  // switching models: free the old one first
        let custom = CustomLocalModels.find(repo)
        let override = ProcessInfo.processInfo.environment["HOLDFAST_MLX_DIR"].map { URL(fileURLWithPath: $0) }
        guard let dir = override ?? custom?.folder ?? modelDir(repo: repo) else { throw HoldfastError("\(repo) is not downloaded; download it in Settings") }
        if custom != nil {
            let inspection = try await CustomModelImport.inspectFolder(dir)
            if let size = inspection.weightBytes, Double(size) > Double(ProcessInfo.processInfo.physicalMemory) * 0.75 {
                throw HoldfastError("This model's weights alone need more than three quarters of this Mac's memory. Choose a smaller model or quantization.")
            }
        }
        let t0 = Date()
        log("loading \(repo) with MLX…")
        let c = try await LLMModelFactory.shared.loadContainer(from: dir, using: #huggingFaceTokenizerLoader())
        let b = MLXBackend(container: c, loadSeconds: Date().timeIntervalSince(t0))
        log(String(format: "loaded in %.1fs", b.loadSeconds))
        cached = b
        loadedRepo = repo
        return b
    }

    private init(container: ModelContainer, loadSeconds: Double) {
        self.container = container
        self.loadSeconds = loadSeconds
    }

    func chat(system: String, user: String, temperature: Double?, onToken: @escaping @Sendable (String) -> Void) async throws -> GenStats {
        let params = GenerateParameters(maxTokens: 2000, temperature: Float(temperature ?? Config.temperature), topP: Float(Config.topP),
                                        topK: Config.topK, presencePenalty: Float(Config.presencePenalty))
        let (text, info) = try await container.perform { (context: ModelContext) -> (String, GenerateCompletionInfo?) in
            let input = try await context.processor.prepare(
                input: UserInput(chat: [.system(system), .user(user)], additionalContext: Config.templateContext))
            var text = ""
            var info: GenerateCompletionInfo?
            for await g in try generate(input: input, parameters: params, context: context) {
                if Task.isCancelled { break }  // Stop: keep what was written so far
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
