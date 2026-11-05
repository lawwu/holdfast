import Foundation

/// `mackb eval <questions.json> --label <name>`: runs every question through
/// retrieval + the current backend and scores it.
///
/// Scoring (deliberately simple and reproducible, no LLM judge):
/// - facts: share of `expect` regex groups found in the answer (case-insensitive)
/// - recall: share of expected session reports among the retrieved passages
/// - cited: the answer cites at least one passage as [n]
/// - unanswerable questions pass if the answer says the information is not there
struct EvalQuestion: Codable {
    var id: String
    var kind: String
    var question: String
    var expect: [String]
    var sessions: [Int]
}

struct EvalResult: Codable {
    var id: String
    var kind: String
    var question: String
    var answer: String
    var facts: Double
    var missed: [String]
    var recall: Double?
    var cited: Bool
    var promptTokens: Int
    var outputTokens: Int
    var tokPerSec: Double
    var seconds: Double
    var sources: [String]
}

func sessionNoteId(_ n: Int) -> String { String(format: "dm-session-%02d", n) }

func runEval(questionsPath: String, label: String, outDir: URL, only: Set<String>) async throws {
    var qs = try JSONDecoder().decode([EvalQuestion].self, from: Data(contentsOf: URL(fileURLWithPath: questionsPath)))
    if !only.isEmpty { qs = qs.filter { only.contains($0.id) } }
    let emb = try await Embedder.load()
    let llm = try await makeBackend()
    var results: [EvalResult] = []
    for q in qs {
        let t0 = Date()
        let a = try await ask(q.question, embedder: emb, llm: llm)
        let secs = Date().timeIntervalSince(t0)
        var hit = 0
        var missed: [String] = []
        for pat in q.expect {
            if a.text.range(of: pat, options: [.regularExpression, .caseInsensitive]) != nil { hit += 1 } else { missed.append(pat) }
        }
        let ids = Set(a.sources.map { $0.noteId })
        let recall: Double? = q.sessions.isEmpty ? nil
            : Double(q.sessions.filter { ids.contains(sessionNoteId($0)) }.count) / Double(q.sessions.count)
        let cited = a.text.range(of: #"\[\d+\]"#, options: .regularExpression) != nil
        let r = EvalResult(id: q.id, kind: q.kind, question: q.question, answer: a.text,
                           facts: Double(hit) / Double(max(q.expect.count, 1)), missed: missed, recall: recall,
                           cited: cited, promptTokens: a.stats.promptTokens, outputTokens: a.stats.outputTokens,
                           tokPerSec: a.stats.tokPerSec, seconds: secs, sources: a.sources.map { citation($0) })
        results.append(r)
        log(String(format: "%@ facts %.0f%% recall %@ cited %@ · %d tok at %.1f tok/s · %.0fs", q.id, r.facts * 100,
                   recall.map { String(format: "%.0f%%", $0 * 100) } ?? "—", cited ? "y" : "n", r.outputTokens, r.tokPerSec, secs))
    }
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try enc.encode(results).write(to: outDir.appendingPathComponent("\(label).json"))

    let n = Double(results.count)
    let facts = results.map(\.facts).reduce(0, +) / n
    let recalls = results.compactMap(\.recall)
    let totalOut = results.map(\.outputTokens).reduce(0, +)
    let genSecs = results.map { Double($0.outputTokens) / max($0.tokPerSec, 0.001) }.reduce(0, +)
    print(String(format: "\n%@: facts %.0f%% · retrieval recall %.0f%% · cited %d/%d · %.1f tok/s · median %.0fs/answer · %.1f min total",
                 label, facts * 100, recalls.reduce(0, +) / Double(max(recalls.count, 1)) * 100,
                 results.filter(\.cited).count, results.count, Double(totalOut) / max(genSecs, 0.001),
                 results.map(\.seconds).sorted()[results.count / 2], results.map(\.seconds).reduce(0, +) / 60))
}
