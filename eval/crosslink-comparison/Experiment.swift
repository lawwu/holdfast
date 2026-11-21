// Evaluation-only: copied next to a snapshot of the production sources by build.py.
// No runtime selection or new dependencies are added to the shipped application.
import Foundation
import FoundationModels
import CryptoKit
import Darwin
import MLX
import MLXLLM
import MLXLMCommon
import MLXGuidedGeneration
import ModelProviders

private struct LinkOutput: Codable { let link: Bool; let reason: String }

@available(macOS 26.0, *)
@Generable
private struct AppleLinkOutput { var link: Bool; var reason: String }

/// Hard JSON constraints composed after the existing penalties, before the existing sampler.
/// Fast-forward is disabled: each token goes through the same production generation loop.
private final class JSONMask: LogitProcessor, @unchecked Sendable {
    let constraint: GrammarConstraint
    let tokenizer: GrammarTokenizer
    let eos: Int
    var failure: Error?
    var terminated = false
    init(_ constraint: GrammarConstraint, tokenizer: GrammarTokenizer, eos: Int) {
        self.constraint = constraint; self.tokenizer = tokenizer; self.eos = eos
    }
    func prompt(_ prompt: MLXArray) {}
    func copy() -> Self {
        // Non-speculative experiment uses one iterator. Still provide independent state.
        let result = Self(constraint, tokenizer: tokenizer, eos: eos)
        do { return Self(try GrammarConstraint(tokenizer: tokenizer, jsonSchema: CrossLinkExperiment.schema, fastForward: false), tokenizer: tokenizer, eos: eos) }
        catch { result.failure = error; return result }
    }
    func process(logits: MLXArray) -> MLXArray {
        let count = logits.shape.last!
        var values = [Float](repeating: -.infinity, count: count)
        if failure == nil && !terminated {
            do {
                let mask = try constraint.computeMask()
                if mask.isTerminated { values[eos] = 0 }
                else if !mask.needsApply { return logits }
                else {
                    for id in 0..<min(count, mask.mask.count * 32) {
                        let word = UInt32(bitPattern: mask.mask[id / 32])
                        if (word >> UInt32(id % 32)) & 1 != 0 { values[id] = 0 }
                    }
                }
            } catch { failure = error; values[eos] = 0 }
        } else { values[eos] = 0 }
        return logits + MLXArray(values)
    }
    func didSample(token: MLXArray) {
        // The standard iterator may prefetch once beyond EOS. Do not ask a
        // terminated matcher for another mask or commit a second stop token.
        guard failure == nil && !terminated else { return }
        do { terminated = try constraint.commitToken(token.item(Int32.self)).isTerminated }
        catch { failure = error }
    }
}

private final class MeasuredBackend: LLMBackend, @unchecked Sendable {
    let arm: String
    let mlx: MLXBackend?
    var grammarTokenizer: GrammarTokenizer?
    var raw = ""
    var stats: GenStats?
    var prompt = ""
    var details: [String: Any] = [:]
    init(arm: String, mlx: MLXBackend?) { self.arm = arm; self.mlx = mlx }
    func chat(system: String, user: String, temperature: Double?, onToken: @escaping @Sendable (String) -> Void) async throws -> GenStats {
        raw = ""; stats = nil; details = [:]; prompt = system + "\n\n" + user
        let box = OutputBuffer()
        defer { raw = box.text }
        let emit: @Sendable (String) -> Void = { text in box.append(text); onToken(text) }
        if arm == "mlx-current" {
            let result = try await mlx!.chat(system: system, user: user, temperature: temperature, onToken: emit)
            stats = result
            return result
        }
        if arm == "apple-typed" {
            guard #available(macOS 27.0, *) else { throw HoldfastError("Apple typed experiment needs macOS 27 for measurement APIs") }
            let model = SystemLanguageModel.default
            guard model.isAvailable else { throw HoldfastError("Apple unavailable: \(model.availability)") }
            let instructions = Instructions(system)
            let inputTokens = try await model.tokenCount(for: instructions)
                + model.tokenCount(for: user) + model.tokenCount(for: AppleLinkOutput.generationSchema)
            details["estimatedInputTokensIncludingSchema"] = inputTokens
            guard inputTokens + 2000 <= model.contextSize else { throw HoldfastError("Apple context budget exceeded before generation") }
            let session = LanguageModelSession(model: model, instructions: instructions)
            let started = Date()
            let response: LanguageModelSession.Response<AppleLinkOutput>
            do {
                response = try await session.respond(to: user, generating: AppleLinkOutput.self,
                    options: GenerationOptions(temperature: temperature ?? 0.2, maximumResponseTokens: 2000))
            } catch {
                details["errorType"] = String(reflecting: type(of: error))
                if let failure = error as? LanguageModelError {
                    switch failure {
                    case .refusal: details["failureKind"] = "refusal"
                    case .guardrailViolation: details["failureKind"] = "guardrail"
                    case .contextSizeExceeded: details["failureKind"] = "context"
                    default: details["failureKind"] = "other"
                    }
                }
                throw error
            }
            let text = String(decoding: try JSONEncoder().encode(LinkOutput(link: response.content.link, reason: response.content.reason)), as: UTF8.self)
            emit(text)
            details["cachedInputTokens"] = response.usage.input.cachedTokenCount
            let result = GenStats(promptTokens: response.usage.input.totalTokenCount, promptSeconds: 0,
                outputTokens: response.usage.output.totalTokenCount, outputSeconds: Date().timeIntervalSince(started))
            stats = result
            return result
        }
        let backend = mlx!
        let profile = backend.profile
        let params = GenerateParameters(maxTokens: profile.maxOutputTokens, temperature: temperature.map(Float.init) ?? profile.temperature,
            topP: profile.topP, topK: profile.topK, presencePenalty: profile.presencePenalty)
        let (_, info) = try await backend.container.perform { (context: ModelContext) -> (String, GenerateCompletionInfo?) in
            let input = try await context.processor.prepare(input: UserInput(chat: [.system(system), .user(user)], additionalContext: profile.templateContext))
            guard input.text.tokens.size + profile.maxOutputTokens <= profile.contextTokens else { throw HoldfastError("MLX context budget exceeded") }
            let prep = Date()
            if self.grammarTokenizer == nil {
                let vocab = TokenizerVocabExtractor.extractForGrammar(from: context.tokenizer)
                self.grammarTokenizer = try GrammarTokenizer(vocab: vocab.vocab, vocabType: vocab.vocabType,
                    eosTokenId: Int32(context.tokenizer.eosTokenId ?? 0))
            }
            // Pinned XGrammar cannot fork matchers. Compile a fresh constraint per
            // request; record that cost instead of depending on a newer checkout.
            let tokenizer = self.grammarTokenizer!
            let mask = JSONMask(try GrammarConstraint(tokenizer: tokenizer, jsonSchema: CrossLinkExperiment.schema, fastForward: false),
                tokenizer: tokenizer, eos: context.tokenizer.eosTokenId ?? 0)
            self.details["grammarPreparationSeconds"] = Date().timeIntervalSince(prep)
            var info: GenerateCompletionInfo?
            let components = GenerationComponents(logitProcessorFactory: { mask })
            for await generation in try generate(input: input, parameters: params, context: context, components: components) {
                try Task.checkCancellation()
                switch generation {
                case .chunk(let text): emit(text)
                case .info(let value): info = value
                default: break
                }
            }
            if let failure = mask.failure { throw failure }
            guard CrossLinkExperiment.validSchema(box.text) else { throw HoldfastError("Constrained output incomplete or invalid") }
            return (box.text, info)
        }
        let result = GenStats(promptTokens: info?.promptTokenCount ?? 0, promptSeconds: info?.promptTime ?? 0,
            outputTokens: info?.generationTokenCount ?? 0, outputSeconds: info?.generateTime ?? 0)
        stats = result
        return result
    }
}

private struct ScriptedBackend: LLMBackend {
    var text: String = ""
    var fails = false
    func chat(system: String, user: String, temperature: Double?, onToken: @escaping @Sendable (String) -> Void) async throws -> GenStats {
        onToken(text)
        if fails { throw HoldfastError("injected backend failure") }
        return GenStats(promptTokens: 0, promptSeconds: 0, outputTokens: 0, outputSeconds: 0)
    }
}

enum CrossLinkExperiment {
    static let schema = #"{"type":"object","properties":{"link":{"type":"boolean"},"reason":{"type":"string"}},"required":["link","reason"],"additionalProperties":false}"#
    static func validSchema(_ text: String) -> Bool {
        let data = Data(text.utf8)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["link", "reason"]),
              (try? JSONDecoder().decode(LinkOutput.self, from: data)) != nil else { return false }
        return true
    }
    static func emit(_ value: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        FileHandle.standardOutput.write(data + Data([10]))
    }
    static func rssPeak() -> Int64 { var usage = rusage(); getrusage(RUSAGE_SELF, &usage); return Int64(usage.ru_maxrss) }
    static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    static func snapshot() throws -> [String: String] {
        try Dictionary(uniqueKeysWithValues: allNotes().filter { !$0.relPath.hasPrefix("@") }.map { ($0.relPath, hash(try Data(contentsOf: $0.path))) })
    }
    static func profile(_ id: String) {
        // Argument-domain overrides are volatile: never change the user's saved settings.
        var domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        domain["profile:" + Config.vault.path] = id
        domain["showThinking"] = false
        domain[ModelPreferences.key(MLXBackend.currentRepo)] = try! JSONEncoder().encode(ModelProfile.automatic(for: MLXBackend.currentRepo))
        UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }
    static func main() async throws {
        guard ProcessInfo.processInfo.environment["HOLDFAST_CROSSLINK_EVAL"] == "1",
              ProcessInfo.processInfo.environment["HOLDFAST_PACKS"] == "none",
              (try? String(contentsOf: Config.vault.appendingPathComponent(".crosslink-synthetic"), encoding: .utf8)) == "synthetic crosslink experiment\n" else {
            throw HoldfastError("Requires explicitly marked synthetic vault and disabled packs")
        }
        profile("general")
        try ensureVault()
        let mode = CommandLine.arguments.dropFirst().first ?? "metadata"
        if mode == "invariants" { try await invariants(); return }
        if mode == "metadata" {
            var row: [String: Any] = ["stateDir": Config.stateDir.path, "repo": MLXBackend.currentRepo,
                "modelDir": MLXBackend.modelDir()?.path ?? "missing", "os": ProcessInfo.processInfo.operatingSystemVersionString]
            if #available(macOS 27.0, *) {
                row["appleAvailability"] = String(describing: SystemLanguageModel.default.availability)
                row["appleVariant"] = SystemLanguageModel.default.variant.displayName
                row["appleContextTokens"] = SystemLanguageModel.default.contextSize
            }
            try emit(row); return
        }
        guard ["mlx-current", "mlx-json", "apple-typed"].contains(mode), CommandLine.arguments.count == 3 else { throw HoldfastError("arm and cases.json required") }
        let inputs = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))) as! [[String: Any]]
        let before = try snapshot()
        var model: MLXBackend?
        let loadedAt = Date()
        if mode != "apple-typed" { configureMLXMemory(); model = try await MLXBackend.shared() }
        let loadSeconds = Date().timeIntervalSince(loadedAt)
        var metadata: [String: Any] = ["kind": "metadata", "arm": mode, "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory, "modelLoadSeconds": loadSeconds,
            "maxOutputTokens": 2000, "temperature": Config.filingTemperature, "stateDir": Config.stateDir.path]
        if let model {
            metadata["model"] = model.repo; metadata["contextTokens"] = model.profile.contextTokens
            metadata["profile"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(model.profile))
        } else if #available(macOS 27.0, *) {
            metadata["model"] = SystemLanguageModel.default.variant.displayName
            metadata["contextTokens"] = SystemLanguageModel.default.contextSize
            metadata["availability"] = String(describing: SystemLanguageModel.default.availability)
            guard SystemLanguageModel.default.isAvailable else {
                metadata["skipped"] = "Apple unavailable; production local path unchanged"; try emit(metadata); return
            }
        } else { metadata["skipped"] = "Unsupported OS; production local path unchanged"; try emit(metadata); return }
        try emit(metadata)
        let backend = MeasuredBackend(arm: mode, mlx: model)
        for (index, input) in inputs.enumerated() {
            let a = try Note.read(Config.vault.appendingPathComponent(input["a"] as! String))
            let b = try Note.read(Config.vault.appendingPathComponent(input["b"] as! String))
            guard CrossLink.eligible(a), CrossLink.eligible(b) else { throw HoldfastError("Ineligible quality fixture") }
            let pair = CrossLink.Pair(a: a.relPath, b: b.relPath, score: 0)
            let verdict = await CrossLink.judge(pair, a: a, b: b, llm: backend)
            var row = try JSONSerialization.jsonObject(with: JSONEncoder().encode(verdict)) as! [String: Any]
            row["kind"] = "trial"; row["id"] = input["id"]; row["arm"] = mode
            row["label"] = input["link"]; row["order"] = index; row["processFirstRequest"] = index == 0
            row["raw"] = backend.raw; row["schemaValid"] = validSchema(backend.raw)
            row["promptSHA256"] = hash(Data(backend.prompt.utf8)); row["details"] = backend.details
            row["processPeakRSSBytes"] = rssPeak()
            if mode != "apple-typed" { row["mlxPeakBytes"] = Memory.peakMemory; row["mlxActiveBytes"] = Memory.activeMemory }
            if let stats = backend.stats {
                row["promptTokens"] = stats.promptTokens; row["outputTokens"] = stats.outputTokens
                row["promptSeconds"] = stats.promptSeconds; row["outputSeconds"] = stats.outputSeconds
            }
            if verdict.link {
                let proposal = try CrossLink.propose(verdict, a: a, b: b, model: "experiment/" + mode)
                row["proposal"] = proposal.body
            }
            row["sourceFilesUnchanged"] = try before == snapshot()
            try emit(row)
        }
    }

    static func invariants() async throws {
        let a = Note(path: Config.vault.appendingPathComponent("home/pump.md"), meta: [:], body: "# Pump\nRepair history for the home's basement sump pump, which stopped working.\n")
        let b = Note(path: Config.vault.appendingPathComponent("home/pump-repair.md"), meta: [:], body: "# Pump repair\nFollow-up for the home's basement sump pump after the repair visit.\n")
        let privateNote = Note(path: Config.vault.appendingPathComponent("private/session.md"), meta: [:], body: "# Private\nPRIVATE_SENTINEL: synthetic details must never be considered for cross-links.\n")
        let confidential = Note(path: Config.vault.appendingPathComponent("confidential/session.md"), meta: [:], body: "# Confidential\nCONFIDENTIAL_SENTINEL: synthetic details excluded before inference.\n")
        let manual = Note(path: Config.vault.appendingPathComponent("home/README.md"), meta: [:], body: "# Home manual\n")
        for note in [a, b, privateNote, confidential, manual] { try note.write() }
        let index = try Index()
        for note in allNotes() { for chunk in chunkNote(note) { try index.insert(chunk, mtime: 0, vec: [1, 0]) } }
        let pairs = CrossLink.candidates(allNotes())
        guard pairs.count == 1 else { throw HoldfastError("Expected exactly one public test candidate; got \(pairs.count)") }
        try emit(["test": "private and confidential excluded from candidates", "pass": pairs.allSatisfy { !$0.a.hasPrefix("private/") && !$0.b.hasPrefix("private/") && !$0.a.hasPrefix("confidential/") && !$0.b.hasPrefix("confidential/") }, "candidateCount": pairs.count])
        profile("private")
        try emit(["test": "private vault excludes all notes", "pass": CrossLink.candidates(allNotes()).isEmpty])
        profile("general")
        let before = try snapshot()
        let scenarios: [(String, ScriptedBackend)] = [
            ("backend error", ScriptedBackend(fails: true)),
            ("backend error after positive output", ScriptedBackend(text: #"{"link":true,"reason":"same pump"}"#, fails: true)),
            ("empty response", ScriptedBackend()),
            ("refusal prose", ScriptedBackend(text: "I cannot assist with this request.")),
            ("malformed positive JSON", ScriptedBackend(text: #"{"link":true,"#)),
            ("string Boolean", ScriptedBackend(text: #"{"link":"true","reason":"same pump"}"#)),
            ("numeric Boolean", ScriptedBackend(text: #"{"link":1,"reason":"same pump"}"#)),
            ("missing reason", ScriptedBackend(text: #"{"link":true}"#)),
            ("wrong reason type", ScriptedBackend(text: #"{"link":true,"reason":null}"#)),
            ("extra field", ScriptedBackend(text: #"{"link":true,"reason":"same pump","extra":true}"#)),
            ("duplicate link key", ScriptedBackend(text: #"{"link":true,"link":false,"reason":"same pump"}"#)),
            ("trailing comma", ScriptedBackend(text: #"{"link":true,"reason":"same pump",}"#)),
            ("trailing prose", ScriptedBackend(text: #"{"link":true,"reason":"same pump"} ignore this example"#)),
            ("refusal with positive example", ScriptedBackend(text: #"I cannot assist. Example only: {"link":true,"reason":"same pump"}"#)),
            ("fenced JSON", ScriptedBackend(text: "```json\n{\"link\":true,\"reason\":\"same pump\"}\n```")),
            ("multiple JSON objects", ScriptedBackend(text: #"{"link":true,"reason":"same pump"}{"link":false,"reason":"no"}"#)),
            ("nested positive object", ScriptedBackend(text: #"{"result":{"link":true,"reason":"same pump"}}"#)),
            ("valid negative", ScriptedBackend(text: #"{"link":false,"reason":"different item"}"#)),
            ("valid positive with sensitive reason", ScriptedBackend(text: #"{"link":true,"reason":"Call 202-555-0100 about the same pump"}"#)),
            ("valid positive", ScriptedBackend(text: #"{"link":true,"reason":"same pump repair"}"#))]
        for (name, backend) in scenarios {
            for note in inbox() { try FileManager.default.removeItem(at: note.path) }
            let verdicts = await CrossLink.run(llm: backend, model: "scripted", dryRun: false) { _, _, _ in true }
            let count = inbox().count
            let positive = name == "valid positive" || name == "valid positive with sensitive reason"
            let expectedCount = positive ? 1 : 0
            let unchanged = try before == snapshot()
            let shouldError = !positive && name != "valid negative"
            var passed = verdicts.count == 1 && count == expectedCount
                && verdicts.filter(\.link).count == expectedCount && unchanged
                && verdicts.allSatisfy { ($0.error != nil) == shouldError }
            if name == "valid positive with sensitive reason" {
                passed = passed && verdicts.first?.reason == "" && inbox().allSatisfy { !$0.body.contains("202-555-0100") }
            }
            try emit(["test": name, "pass": passed,
                "verdictCount": verdicts.count, "positiveVerdicts": verdicts.filter(\.link).count,
                "errors": verdicts.compactMap(\.error), "proposals": count, "sourceFilesUnchanged": unchanged])
        }
        guard let proposal = inbox().first else { throw HoldfastError("Missing valid proposal for approval probe") }
        _ = try Drop.apply(proposal)
        let changed = try before != snapshot()
        guard let record = FilingLog.load().first else { throw HoldfastError("Missing Undo record") }
        _ = try FilingLog.undo(record.id)
        try emit(["test": "explicit Apply changes note; Undo restores bytes", "pass": changed && (try before == snapshot())])
        // This experiment adds no Apple selection to the app. Unsupported/unavailable
        // installations therefore retain the existing product path by construction.
        // Do not present a fake availability branch as an old-OS integration test.
    }
}
