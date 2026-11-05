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
    /// Household fixture: the domain, and the vault paths that hold the answer.
    var domain: String?
    var paths: [String]?
}

struct EvalResult: Codable {
    var id: String
    var kind: String
    var question: String
    var answer: String
    var facts: Double
    var missed: [String]
    var recall: Double?
    /// Share of expected facts present in the passages given to the model:
    /// a section-level retrieval score (session-level `recall` hid misses).
    var contextRecall: Double?
    var badCitations: [Int]?
    var cited: Bool
    var promptTokens: Int
    var outputTokens: Int
    var tokPerSec: Double
    var seconds: Double
    var sources: [String]
    var domain: String?
    /// Share of the expected answer files among the sources the model was given.
    var pathRecall: Double?
    /// Model and mode, so a results folder can be compared across runs.
    var model: String?
    var mode: String?
    var embedder: String?
    var reranker: Bool?
}

/// Which model and embedder answered, from the environment the eval ran in.
func evalModelName() -> String {
    let env = ProcessInfo.processInfo.environment
    switch env["MACKB_BACKEND"] ?? "ollama" {
    case "mlx": return MLXBackend.currentRepo.components(separatedBy: "/").last ?? MLXBackend.currentRepo
    case "gemini": return env["MACKB_GEMINI_MODEL"] ?? "gemini-flash-latest"
    default: return Config.llmModel
    }
}

func sessionNoteId(_ n: Int) -> String { String(format: "dm-session-%02d", n) }

/// `research`: answer with the tool loop (MLX only). `retrievalOnly`: no model
/// at all, only score what search returns (for comparing embedders).
func runEval(questionsPath: String, label: String, outDir: URL, only: Set<String>,
             research: Bool = false, retrievalOnly: Bool = false) async throws {
    var qs = try JSONDecoder().decode([EvalQuestion].self, from: Data(contentsOf: URL(fileURLWithPath: questionsPath)))
    if !only.isEmpty { qs = qs.filter { only.contains($0.id) } }
    let emb = try await Embedder.load()
    let llm: LLMBackend? = retrievalOnly ? nil : try await makeBackend()
    let mode = retrievalOnly ? "retrieval" : research ? "research" : "plain"
    let model = retrievalOnly ? "—" : evalModelName()
    var results: [EvalResult] = []
    for q in qs {
        let t0 = Date()
        let a: Answer
        if retrievalOnly {
            let hits = try await search(q.question, embedder: emb, reranker: await Reranker.shared(), limit: Config.contextChunks)
            a = Answer(text: "", sources: hits, stats: GenStats(promptTokens: 0, promptSeconds: 0, outputTokens: 0, outputSeconds: 0),
                       retrievalSeconds: Date().timeIntervalSince(t0))
        } else if research, let mlx = llm as? MLXBackend {
            a = try await Agent.run(q.question, embedder: emb, backend: mlx) { _ in }
        } else {
            a = try await ask(q.question, embedder: emb, llm: llm!)
        }
        let secs = Date().timeIntervalSince(t0)
        var hit = 0
        var missed: [String] = []
        for pat in q.expect {
            if a.text.range(of: pat, options: [.regularExpression, .caseInsensitive]) != nil { hit += 1 } else { missed.append(pat) }
        }
        let ids = Set(a.sources.map { ($0.noteId as NSString).lastPathComponent })
        let recall: Double? = q.sessions.isEmpty ? nil
            : Double(q.sessions.filter { ids.contains(sessionNoteId($0)) }.count) / Double(q.sessions.count)
        let cited = a.text.range(of: #"\[\d+\]"#, options: .regularExpression) != nil
        let context = a.sources.map(\.text).joined(separator: "\n")
        let contextRecall: Double? = q.kind == "unanswerable" ? nil
            : Double(q.expect.filter { context.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }.count)
              / Double(max(q.expect.count, 1))
        let srcPaths = Set(a.sources.map(\.relPath))
        let pathRecall: Double? = (q.paths ?? []).isEmpty ? nil
            : Double(q.paths!.filter { p in srcPaths.contains { $0 == p || $0.hasSuffix("/" + p) || p.hasSuffix($0) } }.count) / Double(q.paths!.count)
        let r = EvalResult(id: q.id, kind: q.kind, question: q.question, answer: a.text,
                           facts: retrievalOnly ? 0 : Double(hit) / Double(max(q.expect.count, 1)), missed: missed, recall: recall,
                           contextRecall: contextRecall, badCitations: a.badCitations, cited: cited, promptTokens: a.stats.promptTokens, outputTokens: a.stats.outputTokens,
                           tokPerSec: a.stats.tokPerSec, seconds: secs, sources: a.sources.map { citation($0) },
                           domain: q.domain, pathRecall: pathRecall, model: model, mode: mode,
                           embedder: Config.embedSpec.label, reranker: await Reranker.shared() != nil)
        results.append(r)
        log(String(format: "%@ facts %.0f%% context %@ recall %@ cited %@ · %d tok at %.1f tok/s · %.0fs", q.id, r.facts * 100,
                   contextRecall.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                   recall.map { String(format: "%.0f%%", $0 * 100) } ?? "—", cited ? "y" : "n", r.outputTokens, r.tokPerSec, secs))
    }
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try enc.encode(results).write(to: outDir.appendingPathComponent("\(label).json"))

    let n = Double(results.count)
    let facts = results.map(\.facts).reduce(0, +) / n
    let recalls = results.compactMap(\.contextRecall)
    let totalOut = results.map(\.outputTokens).reduce(0, +)
    let genSecs = results.map { Double($0.outputTokens) / max($0.tokPerSec, 0.001) }.reduce(0, +)
    print(String(format: "\n%@: facts %.0f%% · context recall %.0f%% · cited %d/%d · %.1f tok/s · median %.0fs/answer · %.1f min total",
                 label, facts * 100, recalls.reduce(0, +) / Double(max(recalls.count, 1)) * 100,
                 results.filter(\.cited).count, results.count, Double(totalOut) / max(genSecs, 0.001),
                 results.map(\.seconds).sorted()[results.count / 2], results.map(\.seconds).reduce(0, +) / 60))
}

// MARK: - Filing eval

/// `mackb eval-filing <filing.json> --label <name>`: each case is a document
/// dropped into the household fixture; the model decides where it goes and
/// what to save. Scored without an LLM judge:
/// - action: new / append / skip as expected
/// - place: the target path matches `expect_path`
/// - facts: share of `expect_facts` regexes found in the saved text
/// - leaks: any `forbid` regex (account numbers, full names) found in the saved text
struct FilingCase: Codable {
    var id: String
    var file: String
    var convert: String?
    var expect_action: String
    var expect_path: String
    var expect_facts: [String]
    var forbid: [String]
}

struct FilingResult: Codable {
    var id: String
    var file: String
    var expectAction: String
    var action: String
    var path: String
    var actionOK: Bool
    var placeOK: Bool
    var facts: Double
    var missed: [String]
    var leaks: [String]
    var flags: [String]
    var why: String
    var markdown: String
    var error: String?
    var outputTokens: Int
    var seconds: Double
    var model: String
}

func runFilingEval(casesPath: String, label: String, outDir: URL, only: Set<String>) async throws {
    let base = URL(fileURLWithPath: casesPath).deletingLastPathComponent()
    var cases = try JSONDecoder().decode([FilingCase].self, from: Data(contentsOf: URL(fileURLWithPath: casesPath)))
    if !only.isEmpty { cases = cases.filter { only.contains($0.id) } }
    let emb = try await Embedder.load()
    let llm = try await makeBackend()
    let model = evalModelName()
    var results: [FilingResult] = []
    func found(_ pat: String, _ text: String) -> Bool {
        text.range(of: pat, options: [.regularExpression, .caseInsensitive]) != nil
    }
    for c in cases {
        // A converted copy (PDF, PNG, DOCX) sits next to the source as drops/converted/<name>.<ext>.
        var url = base.appendingPathComponent(c.file)
        if let ext = c.convert, ext != "none" {
            let conv = url.deletingLastPathComponent().appendingPathComponent("converted")
                .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "." + ext)
            if FileManager.default.fileExists(atPath: conv.path) { url = conv }
        }
        let t0 = Date()
        var r = FilingResult(id: c.id, file: url.lastPathComponent, expectAction: c.expect_action, action: "error", path: "",
                             actionOK: false, placeOK: false, facts: 0, missed: c.expect_facts, leaks: [], flags: [], why: "",
                             markdown: "", error: nil, outputTokens: 0, seconds: 0, model: model)
        do {
            let text = try await Drop.text(of: url)
            let d = try await Drop.decide(url, text: text, embedder: emb, llm: llm)
            let f = d.filing
            r.action = f.action
            r.path = f.path
            r.why = f.why
            r.markdown = f.markdown
            r.flags = d.flags
            r.outputTokens = d.stats.outputTokens
            r.actionOK = c.expect_action.split(separator: "|").contains { $0 == f.action }  // "append|new": either is right
            if c.expect_action == "skip" {
                r.placeOK = r.actionOK
                r.facts = r.actionOK ? 1 : 0
                r.missed = []
            } else {
                r.placeOK = f.action != "skip" && found(c.expect_path, f.path)
                let saved = f.title + "\n" + f.markdown
                r.missed = c.expect_facts.filter { !found($0, saved) }
                r.facts = c.expect_facts.isEmpty ? 1 : Double(c.expect_facts.count - r.missed.count) / Double(c.expect_facts.count)
                r.leaks = c.forbid.filter { found($0, saved) }
            }
        } catch {
            r.error = "\(error)"
        }
        r.seconds = Date().timeIntervalSince(t0)
        results.append(r)
        log(String(format: "%@ %@ → %@ %@ · action %@ place %@ facts %.0f%% leaks %d · %.0fs", c.id, r.file, r.action, r.path,
                   r.actionOK ? "ok" : "MISS", r.placeOK ? "ok" : "MISS", r.facts * 100, r.leaks.count, r.seconds))
    }
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    try enc.encode(results).write(to: outDir.appendingPathComponent("\(label).json"))
    let n = Double(results.count)
    print(String(format: "\n%@: action %.0f%% · place %.0f%% · facts %.0f%% · leaks %d · errors %d · median %.0fs/file",
                 label, Double(results.filter(\.actionOK).count) / n * 100, Double(results.filter(\.placeOK).count) / n * 100,
                 results.map(\.facts).reduce(0, +) / n * 100, results.map(\.leaks.count).reduce(0, +),
                 results.filter { $0.error != nil }.count, results.map(\.seconds).sorted()[results.count / 2]))
}
