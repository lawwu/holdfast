import Foundation

/// Past questions and answers, one JSON file per vault in its state folder
/// (`.holdfast/history.json`, or Application Support for an in-place vault). Kept out of the indexed notes on purpose: the model's
/// own earlier answers must never come back as evidence for new ones.
struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var question: String
    var answer: String
    /// The answering model's label, e.g. "Qwen 3.8 27B · 4-bit".
    var model: String
    var stats: AnswerStats
    var sources: [HistorySource]
    /// Research mode's tool steps, if it was used.
    var steps: [String]?
    /// The conversation this turn belongs to (nil: a conversation of its own, as before conversations existed).
    var conversationId: UUID?
    /// How the router handled it ("Answered from the closest passages", "Looked deeper…").
    var route: String?
    /// Carries the restriction even when private tool results have no private citation.
    var localOnly: Bool?

    var thread: UUID { conversationId ?? id }

    init(question: String, answer: String, model: String, stats: AnswerStats, sources: [Chunk]) {
        self.question = question
        self.answer = answer
        self.model = model
        self.stats = stats
        self.sources = sources.map(HistorySource.init)
    }

    /// Every word of the query appears in the question, the answer, or a
    /// source title (case- and accent-insensitive).
    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        let hay = ([question, answer] + sources.map(\.title)).joined(separator: "\n")
        return words.allSatisfy { hay.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}

/// The passages an answer cited, as they were when it was written, so its
/// [n] citations still open the right place later.
struct HistorySource: Codable {
    var noteId: String
    var relPath: String
    var title: String
    var anchor: String
    var text: String
    var score: Double?

    init(_ c: Chunk) {
        noteId = c.noteId; relPath = c.relPath; title = c.title; anchor = c.anchor; text = c.text; score = c.score
    }

    var chunk: Chunk { Chunk(noteId: noteId, relPath: relPath, title: title, anchor: anchor, text: text, score: score) }
}

enum History {
    static var file: URL { Config.stateDir.appendingPathComponent("history.json") }

    static func load() -> [HistoryEntry] {
        guard let d = try? Data(contentsOf: file) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([HistoryEntry].self, from: d)) ?? []
    }

    static func save(_ entries: [HistoryEntry]) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? enc.encode(entries).write(to: file, options: .atomic)
    }
}
