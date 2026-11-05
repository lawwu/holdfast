import Foundation

/// Everything tunable lives here, with the reason next to it.
enum Config {
    /// The vault: plain Markdown, the source of truth. Opens in Obsidian.
    /// Override with MACKB_VAULT.
    static var vault: URL {
        if let p = ProcessInfo.processInfo.environment["MACKB_VAULT"] {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("MacKB")
    }

    static var sourcesDir: URL { vault.appendingPathComponent("sources") }
    static var memoryDir: URL { vault.appendingPathComponent("memory") }
    static var inboxDir: URL { vault.appendingPathComponent("inbox") }
    static var mediaDir: URL { vault.appendingPathComponent(".mackb/media") }
    /// The index is a cache rebuilt from the vault; deleting it loses nothing.
    static var indexPath: URL { vault.appendingPathComponent(".mackb/index.sqlite") }

    /// LLM backend. The POC talks to Ollama over localhost (the plan's
    /// "OpenAI-compatible backend"); MLX in-process can slot in behind `LLMBackend`.
    static var ollamaURL: URL {
        URL(string: ProcessInfo.processInfo.environment["MACKB_OLLAMA"] ?? "http://localhost:11434")!
    }
    /// Qwen 3.8 27B as already installed in Ollama (Q4_K_M despite the "q8" in its name).
    static var llmModel: String { ProcessInfo.processInfo.environment["MACKB_LLM"] ?? "qwen38-27b-q8-32k" }

    /// Qwen3-Embedding-0.6B, already in the Hugging Face cache; run in-process by MLX Swift.
    static var embedModelDir: URL? {
        if let p = ProcessInfo.processInfo.environment["MACKB_EMBED_DIR"] { return URL(fileURLWithPath: p) }
        let snaps = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models--Qwen--Qwen3-Embedding-0.6B/snapshots")
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

func ensureVault() throws {
    for d in [Config.sourcesDir, Config.memoryDir, Config.inboxDir, Config.mediaDir] {
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    }
}

/// stderr logging, so stdout stays clean for the MCP server.
func log(_ s: String) {
    FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}
