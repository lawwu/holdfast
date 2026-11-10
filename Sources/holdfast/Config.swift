import Foundation

/// Everything tunable lives here, with the reason next to it.
enum Config {
    /// The vault: plain Markdown, the source of truth. Opens in Obsidian.
    /// Override with HOLDFAST_VAULT.
    /// Set by the app when the user picks a vault; wins over the environment.
    nonisolated(unsafe) static var vaultOverride: URL?

    static var vault: URL {
        if let v = vaultOverride { return v }
        if let p = ProcessInfo.processInfo.environment["HOLDFAST_VAULT"] {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        return Migrate.defaultVault()
    }

    /// Two kinds of vault:
    /// - managed: a folder the app owns. Imports are copied into `sources/`,
    ///   approved memories go to `memory/`, and app state lives in `.holdfast/`.
    /// - in place: an existing folder of notes (e.g. a git repo of notes),
    ///   indexed where it is. The app writes nothing into it: index, history,
    ///   inbox, memories and imports live in Application Support instead.
    /// A folder is managed if it has `sources/` or is empty (a new vault).
    static var inPlace: Bool {
        let key = vault.path
        if let v = inPlaceCache[key] { return v }
        let v = detectInPlace()
        inPlaceCache[key] = v
        return v
    }
    nonisolated(unsafe) private static var inPlaceCache: [String: Bool] = [:]
    private static func detectInPlace() -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: vault.appendingPathComponent("sources").path) { return false }
        let items = (try? fm.contentsOfDirectory(atPath: vault.path))?.filter { !$0.hasPrefix(".") } ?? []
        return !items.isEmpty
    }

    /// Where app state lives: `.holdfast/` in a managed vault, else a per-vault
    /// folder in Application Support (named after the folder plus a path hash).
    static var stateDir: URL {
        guard inPlace else { return vault.appendingPathComponent(".holdfast") }
        var h: UInt64 = 1469598103934665603  // FNV-1a, stable across launches
        for b in vault.standardizedFileURL.path.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Holdfast/vaults")
            .appendingPathComponent("\(vault.lastPathComponent)-\(String(h, radix: 16).prefix(8))")
    }

    static var sourcesDir: URL { inPlace ? stateDir.appendingPathComponent("sources") : vault.appendingPathComponent("sources") }
    static var memoryDir: URL { inPlace ? stateDir.appendingPathComponent("memory") : vault.appendingPathComponent("memory") }
    static var inboxDir: URL { inPlace ? stateDir.appendingPathComponent("inbox") : vault.appendingPathComponent("inbox") }
    static var mediaDir: URL { stateDir.appendingPathComponent("media") }
    /// The index is a cache rebuilt from the vault; deleting it loses nothing.
    static var indexPath: URL {
        stateDir.appendingPathComponent(embedSpec == .qwen3 ? "index.sqlite" : "index-\(embedSpec.rawValue).sqlite")
    }
    /// Chat-template switches: Qwen's thinking off, gpt-oss's reasoning low.
    /// Templates ignore switches they don't use.
    /// Thinking off by default (faster); "Show Thinking" turns it on and shows the reasoning as a step.
    static var templateContext: [String: any Sendable] {
        Thinking.on ? ["enable_thinking": true, "reasoning_effort": "medium"] : ["enable_thinking": false, "reasoning_effort": "low"]
    }
    /// Filing a dropped file wants exact JSON and a steady choice of place.
    static let filingTemperature = 0.2

    /// Ollama, one of the two LLM backends (the other is MLX in-process; see
    /// `MLXBackend`). The app's Settings window picks between them.
    static var ollamaURL: URL {
        URL(string: ProcessInfo.processInfo.environment["HOLDFAST_OLLAMA"] ?? "http://localhost:11434")!
    }
    /// Qwen 3.8 27B as already installed in Ollama: 8-bit (a 29 GB blob), though
    /// Ollama's metadata labels it Q4_K_M.
    static var llmModel: String { ProcessInfo.processInfo.environment["HOLDFAST_LLM"] ?? "qwen38-27b-q8-32k" }

    /// The embedding model: Qwen3-Embedding-0.6B by default, or Google's
    /// EmbeddingGemma-300m with HOLDFAST_EMBED=embeddinggemma (each has its own index).
    static var embedSpec: EmbedSpec {
        EmbedSpec(rawValue: ProcessInfo.processInfo.environment["HOLDFAST_EMBED"] ?? "") ?? .qwen3
    }

    /// The embedding model's folder in the Hugging Face cache; run in-process by MLX Swift.
    static var embedModelDir: URL? {
        if let p = ProcessInfo.processInfo.environment["HOLDFAST_EMBED_DIR"] { return URL(fileURLWithPath: p) }
        let snaps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models--\(embedSpec.repo.replacingOccurrences(of: "/", with: "--"))/snapshots")
        guard let first = try? FileManager.default.contentsOfDirectory(atPath: snaps.path).sorted().last else { return nil }
        return snaps.appendingPathComponent(first)
    }
    /// Qwen3-Embedding wants an instruction on the query side only.
    static let queryInstruction = "Given a question, retrieve transcript passages that answer it"

    /// Transcript chunking: group segments into ~this many seconds per chunk,
    /// so every chunk starts on a timestamp a citation can jump to.
    static let chunkSeconds: Double = 60
    /// Transcript segments: break a line after a pause this long, or at this length.
    static let segmentPause: Double = 0.8
    static let segmentMaxSeconds: Double = 20

    /// Retrieval: reciprocal-rank-fusion constant and how many chunks go to the LLM.
    static let rrfK: Double = 60
    static let contextChunks = 8

    /// Q&A sampling for Qwen 3.8 with thinking off, per its model card.
    static let temperature = 0.7
    static let topP = 0.8
    static let topK = 20
    static let presencePenalty = 1.5
}

/// Answer models offered in Settings: MLX conversions on Hugging Face whose
/// architectures MLX Swift supports (checked 2026-11-05). Sizes are the repo
/// download; memory in use is about the same plus a few GB of context.
struct MLXModelSpec: Identifiable, Hashable {
    let repo: String
    let name: String
    let detail: String
    let sizeGB: Double
    let blurb: String
    var id: String { repo }

    /// The measured models, best first (Recommend.swift, from the household eval), then one that isn't measured.
    static let shortList: [MLXModelSpec] = Recommend.ranked.map { m in
        MLXModelSpec(repo: m.repo, name: m.name, detail: m.detail, sizeGB: m.sizeGB, blurb: Recommend.summary(m))
    } + [MLXModelSpec(repo: "mlx-community/Qwen3.8-27B-8bit", name: "Qwen 3.8 27B", detail: "8-bit", sizeGB: 29.5,
                      blurb: "The 4-bit model at higher precision; about half the speed. Not measured by the eval.")]
    /// Before a model is chosen: the one recommended for this Mac's memory.
    static let fallback = find(Recommend.pick()?.best.repo ?? "") ?? find("mlx-community/Qwen3.8-27B-4bit") ?? shortList[0]
    static func find(_ repo: String) -> MLXModelSpec? { shortList.first { $0.repo == repo } }
}

enum TranscriptionModel: String, CaseIterable, Identifiable {
    case parakeetV3 = "parakeet-v3", parakeetV2 = "parakeet-v2"
    var id: String { rawValue }
    var name: String { self == .parakeetV3 ? "Parakeet v3" : "Parakeet v2" }
    var blurb: String {
        self == .parakeetV3 ? "Multilingual (25 European languages). Recommended."
            : "English only. Use it if your recordings are all English."
    }
    /// FluidAudio's CoreML model folder, to tell whether it's downloaded.
    var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FluidAudio/Models")
            .appendingPathComponent(self == .parakeetV3 ? "parakeet-tdt-0.6b-v3" : "parakeet-tdt-0.6b-v2")
    }
}

/// Choices made in the app's Settings window (UserDefaults). The CLI runs
/// under its own defaults domain, so it keeps the defaults unless told otherwise.
enum Prefs {
    static var searchByMeaning: Bool {
        get { UserDefaults.standard.object(forKey: "searchByMeaning") == nil || UserDefaults.standard.bool(forKey: "searchByMeaning") }
        set { UserDefaults.standard.set(newValue, forKey: "searchByMeaning") }
    }
    static var mlxRepo: String {
        get { UserDefaults.standard.string(forKey: "mlxRepo") ?? MLXModelSpec.fallback.repo }
        set { UserDefaults.standard.set(newValue, forKey: "mlxRepo") }
    }
    static var rerankerOn: Bool {
        get { UserDefaults.standard.object(forKey: "rerankerOn") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "rerankerOn") }
    }
    static var transcription: TranscriptionModel {
        get { UserDefaults.standard.string(forKey: "transcription").flatMap(TranscriptionModel.init) ?? .parakeetV3 }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "transcription") }
    }
    /// Where the app downloads MLX models (directly, not via the HF cache, so
    /// nothing is stored twice).
    static var modelsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Holdfast/models")
    }
}

func ensureVault() throws {
    Migrate.vaultState(Config.vault)
    // For an in-place vault these all live in Application Support, not the vault.
    for d in [Config.sourcesDir, Config.memoryDir, Config.inboxDir, Config.mediaDir] {
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    }
}

/// stderr logging, so stdout stays clean for the MCP server.
func log(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

enum EmbedSpec: String {
    case qwen3 = "qwen3-0.6b"
    case embeddingGemma = "embeddinggemma"
    var repo: String { self == .qwen3 ? "Qwen/Qwen3-Embedding-0.6B" : "mlx-community/embeddinggemma-300m-bf16" }
    var label: String { self == .qwen3 ? "Qwen3-Embedding-0.6B" : "EmbeddingGemma-300m" }
}
