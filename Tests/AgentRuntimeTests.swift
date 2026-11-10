import Foundation

typealias R = AgentRuntime

func expect(_ condition: Bool, _ message: String) throws {
    if !condition { throw R.Failure("TEST FAILED: " + message) }
}

actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}

actor Model: R.Model {
    let name: String
    let isLocal: Bool
    var replies: [Result<R.Reply, Error>]
    private(set) var requests: [R.Request] = []
    init(_ name: String = "fake-local", local: Bool = true, replies: [Result<R.Reply, Error>]) {
        self.name = name; self.isLocal = local; self.replies = replies
    }
    func respond(to request: R.Request, onText: @escaping @Sendable (String) -> Void) async throws -> R.Reply {
        requests.append(request)
        guard !replies.isEmpty else { throw R.Failure("unexpected model request") }
        let reply = try replies.removeFirst().get()
        onText(reply.text)
        return reply
    }
}

final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [R.Event] = []
    func add(_ event: R.Event) { lock.lock(); defer { lock.unlock() }; values.append(event) }
    var all: [R.Event] { lock.lock(); defer { lock.unlock() }; return values }
}

func call(_ name: String = "echo", _ arguments: String = #"{"text":"hello"}"#, id: String = UUID().uuidString) -> R.Call {
    .init(id: id, name: name, arguments: arguments)
}

func tool(_ counter: Counter, name: String = "echo", localOnly: Bool = false) -> R.Tool {
    R.Tool(spec: .init(name: name, description: "Test tool", fields: ["text": "Text"], required: ["text"])) { args in
        await counter.increment()
        return .init(text: args["text"]!, localOnly: localOnly)
    }
}

func results(_ messages: [R.Message]) -> [R.ToolResult] {
    messages.compactMap { if case .tool(_, let result) = $0 { return result }; return nil }
}

@main struct AgentRuntimeTests {
    static func main() async throws {
        try await conversation()
        try await validation()
        try await toolFailure()
        try await budgets()
        try await truncation()
        try await privacy()
        try await failClosed()
        try await recovery()
        try await cancellation()
        try await concurrency()
        try await journalFailure()
        try await journal()
        try registry()
        print("PASS: 13 agent runtime checks (no model, GPU, network or real vault)")
    }

    static func conversation() async throws {
        let count = Counter(), events = Events()
        let model = Model(replies: [.success(.init(calls: [call(id: "call-1")])),
                                    .success(.init(text: "done")), .success(.init(text: "follow-up"))])
        let session = try R.Session(system: "test", model: model, tools: [tool(count)])
        let first = try await session.run("first", record: { events.add($0) })
        let second = try await session.run("second")
        try expect(first.text == "done" && second.text == "follow-up", "answers")
        try expect(await count.value == 1, "follow-up must not replay tools")
        let requests = await model.requests
        try expect(results(requests[2].messages).first?.text == "hello", "follow-up retains tool result")
        let history = await session.transcript()
        let copy = try JSONDecoder().decode([R.Message].self, from: JSONEncoder().encode(history))
        try expect(copy == history, "transcript round trip")
        let names = events.all.map { event in
            switch event { case .toolStarted: return "start"; case .toolFinished: return "end"; default: return "other" }
        }
        try expect(names.firstIndex(of: "start")! < names.firstIndex(of: "end")!, "intent precedes result")
    }

    static func validation() async throws {
        let count = Counter()
        let calls = [call("echo", "{"), call("echo", "{}"), call("echo", #"{"text":42}"#),
                     call("echo", #"{"text":"ok","extra":"no"}"#), call("unregistered")]
        let model = Model(replies: [.success(.init(calls: calls)), .success(.init(text: "corrected"))])
        let session = try R.Session(system: "test", model: model, tools: [tool(count)])
        _ = try await session.run("test")
        try expect(await count.value == 0, "invalid or unknown calls must not execute")
        let messages = await model.requests[1].messages
        try expect(results(messages).count == 5 && results(messages).allSatisfy(\.isError), "errors return to model")
    }

    static func toolFailure() async throws {
        let count = Counter()
        var failing = tool(count)
        failing.execute = { _ in await count.increment(); throw R.Failure("try a different query") }
        let model = Model(replies: [.success(.init(calls: [call()])), .success(.init(text: "handled"))])
        let session = try R.Session(system: "test", model: model, tools: [failing])
        _ = try await session.run("test")
        try expect(await count.value == 1, "tool is never automatically retried")
        try expect(await results(model.requests[1].messages).first?.isError == true, "tool error is visible")
    }

    static func budgets() async throws {
        let count = Counter()
        let model = Model(replies: [.success(.init(calls: [call(), call()])), .success(.init(text: "bounded"))])
        let session = try R.Session(system: "test", model: model, tools: [tool(count)], policy: .init(maxToolCalls: 1))
        let answer = try await session.run("test")
        try expect(await count.value == 1, "per-run call limit applies within a batch")
        try expect(await model.requests[1].tools.isEmpty, "final request disables tools")
        try expect(answer.stop == .limit, "limit stop reason")
        let stubborn = Model(replies: [.success(.init(calls: [call()]))])
        let zero = try R.Session(system: "test", model: stubborn, tools: [tool(count)], policy: .init(maxToolRounds: 0))
        _ = try await zero.run("test")
        try expect(await count.value == 1, "model cannot invoke disabled tools")
    }

    static func truncation() async throws {
        let count = Counter()
        let model = Model(replies: [.success(.init(calls: [call()], truncated: true)), .success(.init(text: "repaired"))])
        let session = try R.Session(system: "test", model: model, tools: [tool(count)])
        _ = try await session.run("test")
        try expect(await count.value == 0, "truncated response cannot execute even valid JSON")
        try expect(await results(model.requests[1].messages).first?.isError == true, "truncation is repairable")
    }

    static func privacy() async throws {
        let edits = Counter(), reads = Counter()
        let remote = Model("remote", local: false, replies: [.success(.init(calls: [call("propose"), call("private_read")]))])
        let local = Model(replies: [.success(.init(text: "local answer")), .success(.init(text: "still local"))])
        var policy = R.Policy()
        policy.makeLocalModel = { local }
        let session = try R.Session(system: "test", model: remote,
                                    tools: [tool(edits, name: "propose"), tool(reads, name: "private_read", localOnly: true)], policy: policy)
        _ = try await session.run("test")
        _ = try await session.run("follow-up")
        try expect(await remote.requests.count == 1, "private result never sent remotely")
        try expect(await local.requests.count == 2, "locality persists on follow-up")
        let editCount = await edits.value, readCount = await reads.value
        try expect(editCount == 1 && readCount == 1, "model switch preserves completed tools")
        try expect(await results(local.requests[0].messages).count == 2, "local model sees results")
    }

    static func failClosed() async throws {
        let remote = Model("remote", local: false, replies: [])
        let session = try R.Session(system: "private", model: remote, tools: [], localOnly: true)
        do { _ = try await session.run("test"); throw R.Failure("should refuse remote") }
        catch { try expect(error.localizedDescription.contains("local model"), "must fail for locality") }
        var policy = R.Policy(); policy.makeLocalModel = { remote }
        let wrong = try R.Session(system: "private", model: remote, tools: [], localOnly: true, policy: policy)
        do { _ = try await wrong.run("test"); throw R.Failure("should reject wrong factory") }
        catch { try expect(error.localizedDescription.contains("Local-only"), "factory cannot bypass privacy") }
        try expect(await remote.requests.isEmpty, "no remote request on policy failure")
    }

    static func recovery() async throws {
        let edits = Counter()
        let remote = Model("remote", local: false, replies: [.success(.init(calls: [call()])), .failure(URLError(.timedOut))])
        let local = Model(replies: [.success(.init(text: "recovered"))])
        var policy = R.Policy(); policy.recoverModel = { _, _ in local }
        let session = try R.Session(system: "test", model: remote, tools: [tool(edits)], policy: policy)
        _ = try await session.run("test")
        try expect(await edits.value == 1, "recovery retries model, not tool")
        try expect(await results(local.requests[0].messages).count == 1, "recovery retains result")
    }

    static func cancellation() async throws {
        let first = Counter(), second = Counter()
        var cancel = tool(first, name: "cancel")
        cancel.execute = { _ in
            await first.increment()
            withUnsafeCurrentTask { $0?.cancel() }
            return .init(text: "Completed before cancellation")
        }
        let model = Model(replies: [.success(.init(calls: [call("cancel"), call("later")]))])
        let session = try R.Session(system: "test", model: model, tools: [cancel, tool(second, name: "later")])
        let task = Task { try await session.run("test") }
        let answer = try await task.value
        try expect(answer.stop == .cancelled, "cancellation is a distinct outcome")
        let firstCount = await first.value, secondCount = await second.value
        try expect(firstCount == 1 && secondCount == 0, "cancellation stops subsequent tools")
        let messages = await session.transcript()
        try expect(results(messages).count == 2 && results(messages)[1].isError, "cancelled calls have outcomes")

        // A tool can report cancellation without the caller task's flag being set.
        var interrupted = tool(first, name: "interrupt")
        interrupted.execute = { _ in throw CancellationError() }
        let model2 = Model(replies: [.success(.init(calls: [call("interrupt"), call("later")]))])
        let session2 = try R.Session(system: "test", model: model2, tools: [interrupted, tool(second, name: "later")])
        let answer2 = try await session2.run("test")
        try expect(answer2.stop == .cancelled, "tool cancellation ends the run")
        try expect(await second.value == 0, "tool cancellation stops the rest of the batch")
    }

    static func concurrency() async throws {
        let entered = Gate(), release = Gate(), count = Counter()
        var wait = tool(count)
        wait.execute = { _ in await entered.open(); await release.wait(); return .init(text: "released") }
        let model = Model(replies: [.success(.init(calls: [call()])), .success(.init(text: "done"))])
        let session = try R.Session(system: "test", model: model, tools: [wait])
        let task = Task { try await session.run("first") }
        await entered.wait()
        do { _ = try await session.run("second"); throw R.Failure("should reject concurrent run") }
        catch { try expect(error.localizedDescription.contains("already running"), "busy session rejects overlap") }
        await release.open()
        _ = try await task.value
    }

    static func journalFailure() async throws {
        let count = Counter()
        let model = Model(replies: [.success(.init(calls: [call()]))])
        let session = try R.Session(system: "test", model: model, tools: [tool(count)])
        do {
            _ = try await session.run("test", record: { event in
                if case .toolStarted = event { throw R.Failure("disk full") }
            })
            throw R.Failure("should fail recording intent")
        } catch { try expect(error.localizedDescription == "disk full", "journal failure is not a tool error") }
        try expect(await count.value == 0, "no effect without recorded intent")
        do { _ = try await session.run("retry"); throw R.Failure("should reject reuse") }
        catch { try expect(error.localizedDescription.contains("Start a new session"), "failed run never silently replays") }

        let executed = Counter()
        let model2 = Model(replies: [.success(.init(calls: [call()]))])
        let uncertain = try R.Session(system: "test", model: model2, tools: [tool(executed)])
        do {
            _ = try await uncertain.run("test", record: { event in
                if case .toolFinished = event { throw R.Failure("outcome write failed") }
            })
            throw R.Failure("should fail recording outcome")
        } catch { try expect(error.localizedDescription == "outcome write failed", "outcome failure ends run") }
        try expect(await executed.value == 1, "the effect happened once before logging failed")
        do { _ = try await uncertain.run("retry"); throw R.Failure("should reject uncertain reuse") }
        catch { try expect(error.localizedDescription.contains("Start a new session"), "uncertain effects are not replayed") }
    }

    static func journal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try AgentJournal(directory: directory, system: "test", model: "fake", tools: [], prior: [])
        try journal.append(.started); try journal.append(.text("transient")); try journal.append(.finished(.completed))
        let lines = try String(contentsOf: journal.url, encoding: .utf8).split(separator: "\n")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let entries = try lines.map { try decoder.decode(AgentJournal.Entry.self, from: Data($0.utf8)) }
        try expect(entries.map(\.sequence) == [0, 1, 2], "monotonic durable events, no token deltas")
        let attributes = try FileManager.default.attributesOfItem(atPath: journal.url.path)
        try expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "private journal permissions")
    }

    static func registry() throws {
        let count = Counter(), model = Model(replies: [])
        do {
            _ = try R.Session(system: "test", model: model, tools: [tool(count), tool(count)])
            throw R.Failure("should reject duplicate tools")
        } catch { try expect(error.localizedDescription.contains("unique"), "duplicate tool names refused") }
    }
}
