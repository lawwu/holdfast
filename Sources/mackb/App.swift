import AppKit
import AVFoundation
import SwiftUI

// MARK: - App

struct MacKBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup("Holdfast") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 1120, minHeight: 700)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView().environmentObject(store)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Vault") {
                Button("Import Files or Folder…") { store.importFiles() }.keyboardShortcut("i")
                Button("Bulk Import…") { store.showBulkImport = true }.keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Suggest Links Between Notes") { store.runCrossLink() }
                Button("Add Link…") { store.showLinkSheet = true }.keyboardShortcut("l")
                Button("Rebuild Index") { store.rebuildIndex() }
                Button("Open Drop Folder") { store.revealDrop() }.keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Choose Vault…") { store.chooseVault() }
            }
            CommandMenu("Note") {
                Button("Back") { store.goBack() }.keyboardShortcut("[").disabled(store.backStack.isEmpty)
                Button("Forward") { store.goForward() }.keyboardShortcut("]").disabled(store.forwardStack.isEmpty)
                Button(store.showList ? "Hide File List" : "Show File List") { store.showList.toggle() }
                    .keyboardShortcut("\\", modifiers: [.command, .shift])
                Divider()
                Button("Command Palette…") { store.showPalette = true }.keyboardShortcut("p")
                Button("Quick Open…") { store.quickOpenNewTab = false; store.showQuickOpen = true }.keyboardShortcut("o")
                Button("Open in New Tab…") { store.quickOpenNewTab = true; store.showQuickOpen = true }.keyboardShortcut("t")
                Button("Close Tab") { store.closeTab(store.activeTab) }.keyboardShortcut("w").disabled(store.tabs.isEmpty)
                Button("Next Tab") { store.cycleTab(1) }.keyboardShortcut(.tab, modifiers: .control).disabled(store.tabs.count < 2)
                Button("Previous Tab") { store.cycleTab(-1) }.keyboardShortcut(.tab, modifiers: [.control, .shift]).disabled(store.tabs.count < 2)
                Divider()
                Button("New Note") { store.createNote(near: store.opened?.note) }.keyboardShortcut("n", modifiers: [.command, .shift])
                Button(store.editing ? "Reading View" : "Editing View") { store.editing.toggle() }.keyboardShortcut("e")
                Divider()
                Button("Files") { store.pane = .files }.keyboardShortcut("1", modifiers: [.command, .option])
                Button("Graph") { store.pane = .graph }.keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A bare executable needs this to get a Dock icon and keyboard focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = renderAppIcon()
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum Pane: String, CaseIterable, Identifiable {
    case ask = "Ask", history = "History", files = "Files", tables = "Tables", graph = "Graph", library = "Library", inbox = "Inbox"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .ask: return "bubble.left.and.text.bubble.right"
        case .history: return "clock.arrow.circlepath"
        case .files: return "folder"
        case .tables: return "tablecells"
        case .graph: return "point.3.connected.trianglepath.dotted"
        case .library: return "books.vertical"
        case .inbox: return "tray"
        }
    }
}

/// Where answers are generated: an MLX model inside the app (which one is
/// `Store.mlxRepo`), or the Ollama server.
enum Backend: String, CaseIterable, Identifiable {
    case mlx = "Qwen 3.8 27B · MLX (in app)"
    case ollama = "Qwen 3.8 27B · Ollama"
    case remote = "A model on another Mac"
    var id: String { rawValue }
}

struct AnswerStats: Codable {
    var passages: Int
    var tokens: Int
    var tokPerSec: Double
    var seconds: Double
}

/// One tab: the note it shows and where it has been.
struct ThreadRef: Identifiable { var id: UUID }

/// Research with whichever model answers: in-process MLX, or a model on another Mac.
func runResearch(_ q: String, embedder: Embedder?, llm: LLMBackend, prior: [(q: String, a: String)],
                 onEvent: @escaping @Sendable (Agent.Event) -> Void) async throws -> Answer {
    if llm is RemoteBackend { return try await RemoteAgent.run(q, embedder: embedder, prior: prior, onEvent: onEvent) }
    guard let mlx = llm as? MLXBackend else { throw MacKBError("Research needs an MLX model or a model on another Mac") }
    return try await Agent.run(q, embedder: embedder, backend: mlx, prior: prior, onEvent: onEvent)
}

struct NoteTab: Identifiable {
    let id = UUID()
    var opened: Opened
    var back: [Opened] = []
    var forward: [Opened] = []
}

struct Opened: Equatable, Identifiable {
    var id: String { note.path.path + "#" + (anchor ?? "") }
    var note: Note
    var anchor: String?
    static func == (a: Opened, b: Opened) -> Bool { a.note.path == b.note.path && a.anchor == b.anchor }
}

// MARK: - State

@MainActor
final class Store: ObservableObject {
    @Published var vault: URL
    @Published var pane: Pane? = .ask
    @Published var notes: [Note] = []
    @Published var inboxItems: [Note] = []
    @Published var question = ""
    @Published var answer = ""
    @Published var sources: [Chunk] = []
    @Published var askedQuestion = ""
    @Published var answerStats: AnswerStats?
    @Published var warning: String?
    @Published var busy: String?
    @Published var error: String?
    /// Open notes, one per tab, each with its own Back/Forward history.
    @Published var tabs: [NoteTab] = []
    @Published var activeTab: UUID?
    /// The note in the active tab. Setting another note navigates in that tab
    /// (recording history); setting nil closes the tab.
    var opened: Opened? {
        get { tabs.first { $0.id == activeTab }?.opened }
        set { navigate(to: newValue) }
    }
    /// A note shown in a preview card (option-click a link, or hover a link chip).
    @Published var preview: Opened?
    @Published var showPalette = false
    /// Quick Open puts its pick in a new tab (the + in the tab bar, ⌘T).
    @Published var quickOpenNewTab = false
    /// The middle pane (Ask, Files, Library…) beside an open note; hide it to
    /// read the note wide. The sidebar has its own button.
    @Published var showList = UserDefaults.standard.object(forKey: "showList") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showList, forKey: "showList") }
    }
    var backStack: [Opened] { tabs.first { $0.id == activeTab }?.back ?? [] }
    var forwardStack: [Opened] { tabs.first { $0.id == activeTab }?.forward ?? [] }
    @Published var searchText = ""
    @Published var results: [Chunk] = []
    @Published var backend: Backend = .mlx {
        didSet { UserDefaults.standard.set(backend.rawValue, forKey: "backend") }
    }
    @Published var mlxRepo = Prefs.mlxRepo { didSet { Prefs.mlxRepo = mlxRepo } }
    @Published var rerankerOn = Prefs.rerankerOn { didSet { Prefs.rerankerOn = rerankerOn } }
    @Published var transcription = Prefs.transcription { didSet { Prefs.transcription = transcription } }
    /// In-flight model downloads: repo → fraction done.
    @Published var downloads: [String: Double] = [:]
    @Published var downloadErrors: [String: String] = [:]
    @Published var history: [HistoryEntry] = []
    /// The history entry on screen in Ask, if any.
    @Published var currentHistoryId: UUID?
    @Published var historySearch = ""
    /// Links between notes, rebuilt on load and after every save.
    @Published var links = LinkGraph()
    /// Notes open in the editor rather than the reader (⌘E).
    @Published var editing = false
    @Published var showQuickOpen = false
    /// Research mode: answer in steps with tools (search, read, list, query CSVs).
    @Published var research = UserDefaults.standard.bool(forKey: "research") {
        didSet { UserDefaults.standard.set(research, forKey: "research") }
    }
    /// The tool steps of the answer on screen.
    @Published var steps: [String] = []
    private var reindexTask: Task<Void, Never>?
    /// The vault's default profile (general or counseling); see Profile.swift.
    @Published var profile = Profile.general { didSet { Profile.vaultDefault = profile } }
    @Published var showLinkSheet = false
    @Published var linkText = ""
    @Published var indexCounts = (chunks: 0, notes: 0, vectors: 0)
    /// The drop folder: what is being filed now, and files that failed.
    @Published var dropStatus: String?
    /// Approved filings, newest first (undo lives here).
    @Published var filings: [FilingRecord] = []
    /// Open follow-ups due soon or overdue, from every note.
    @Published var upcoming: [FollowUp] = []
    /// Senders filed to the same place often enough to offer a rule.
    @Published var ruleSuggestions: [Rules.Candidate] = []
    @Published var notice: String?
    /// How the last request was handled (direct answer, research, a job), shown under the answer.
    @Published var routeNote: String?
    /// The conversation on screen: its earlier turns (the live turn is askedQuestion/answer/sources).
    @Published var turns: [HistoryEntry] = []
    @Published var conversationId: UUID?
    /// When the current turn started, for the elapsed-time readout.
    @Published var turnStarted: Date?
    /// A past conversation opened for reading while another is still generating.
    @Published var reading: ThreadRef?
    /// The answer being generated, so Stop can cancel it.
    private var askTask: Task<Void, Never>?

    /// Stops the answer mid-way; what was written so far is kept (and saved, marked as stopped).
    func stopAsk() { askTask?.cancel() }

    /// Past conversations, newest first: each with its first question, latest turn and length.
    var conversations: [(first: HistoryEntry, latest: HistoryEntry, count: Int)] {
        var order: [UUID] = []
        var byThread: [UUID: [HistoryEntry]] = [:]
        for e in history {  // newest first
            if byThread[e.thread] == nil { order.append(e.thread) }
            byThread[e.thread, default: []].append(e)
        }
        return order.compactMap { t in
            guard let es = byThread[t], let latest = es.first, let first = es.last else { return nil }
            return (first, latest, es.count)
        }
    }
    /// Filing queue progress: files handled since the queue was last empty, and pause.
    @Published var queueDone = 0
    @Published var queueLeft = 0
    @Published var dropPaused = false
    /// "Bring in as-is" import progress (done, total, current file).
    @Published var importProgress: (done: Int, total: Int, file: String)?
    @Published var showBulkImport = false
    @Published var showRemoteSetup = false
    /// What the progress bar is counting ("Importing", "Checking pairs"…), and a stop request.
    @Published var jobTitle = "Importing"
    private var jobStop = false
    @Published var dropErrors: [String] = []
    private var dropTimer: Timer?
    private var filing = false

    private var embedder: Embedder?
    let player = AVPlayer()

    init() {
        if let p = UserDefaults.standard.string(forKey: "vault") {
            vault = URL(fileURLWithPath: p)
        } else {
            vault = Config.vault
        }
        if let b = UserDefaults.standard.string(forKey: "backend"), let v = Backend(rawValue: b) { backend = v }
        reload()
        dropTimer = Timer.scheduledTimer(withTimeInterval: Drop.pollSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fileDropped() }
        }
    }

    func reload() {
        Config.vaultOverride = vault
        try? ensureVault()
        notes = allNotes()
        links = LinkGraph(notes: notes)
        vaultDomains = Array(Set(notes.compactMap(\.domain))).sorted()
        for i in tabs.indices {  // tabs show the latest copy of their notes
            if let fresh = notes.first(where: { $0.path == tabs[i].opened.note.path }) {
                tabs[i].opened = Opened(note: fresh, anchor: tabs[i].opened.anchor)
            }
        }
        inboxItems = inbox()
        filings = FilingLog.load()
        upcoming = Upcoming.scan(notes)
        ruleSuggestions = Rules.suggestions()
        indexCounts = (try? Index().count()) ?? (0, 0, 0)
        history = History.load()
        if profile != Profile.vaultDefault { profile = Profile.vaultDefault }
    }

    // MARK: models

    /// Short label for the model answering now, e.g. "Qwen 3.8 27B · 4-bit".
    var modelLabel: String {
        if backend == .ollama { return "Qwen 3.8 27B · Ollama" }
        if backend == .remote { return "\(Remote.model.split(separator: "/").last.map(String.init) ?? "Model") · on \(Remote.host)" }
        guard let spec = MLXModelSpec.find(mlxRepo) else { return mlxRepo.components(separatedBy: "/").last ?? mlxRepo }
        return "\(spec.name) · \(spec.detail)"
    }

    func isDownloaded(_ repo: String) -> Bool { MLXBackend.modelDir(repo: repo) != nil }

    func selectMLX(_ repo: String) {
        guard isDownloaded(repo) else { return }
        mlxRepo = repo
        backend = .mlx
    }

    func download(_ spec: MLXModelSpec) {
        guard downloads[spec.repo] == nil else { return }
        downloads[spec.repo] = 0
        downloadErrors[spec.repo] = nil
        let repo = spec.repo
        Task {
            do {
                try await MLXBackend.download(repo: repo) { f in
                    Task { @MainActor in if self.downloads[repo] != nil { self.downloads[repo] = f } }
                }
            } catch {
                downloadErrors[repo] = "\(error)"
            }
            downloads[repo] = nil
        }
    }

    private func getEmbedder() async -> Embedder? {
        if embedder == nil {
            busy = "Loading the embedding model…"
            embedder = try? await Embedder.load()
        }
        return embedder
    }

    private func getLLM() async throws -> LLMBackend {
        switch backend {
        case .ollama: return OllamaBackend()
        case .remote:
            guard Remote.url != nil, !Remote.model.isEmpty else { throw MacKBError("Set up the model on another Mac first (model menu → Another Mac → Set Up…)") }
            return RemoteBackend()
        case .mlx:
            if !(MLXBackend.isLoaded && MLXBackend.loadedRepo == mlxRepo) {
                busy = "Loading \(modelLabel) into memory…"
            }
            return try await MLXBackend.shared()
        }
    }

    func runAsk() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, busy == nil else { return }
        answer = ""
        sources = []
        answerStats = nil
        warning = nil
        error = nil
        // A follow-up: the finished turn on screen becomes part of the conversation.
        if let id = currentHistoryId, let done = history.first(where: { $0.id == id }), !turns.contains(where: { $0.id == id }) {
            turns.append(done)
        }
        let convo = conversationId ?? UUID()
        conversationId = convo
        let prior = turns.map { (q: $0.question, a: $0.answer) }
        askedQuestion = q
        question = ""
        currentHistoryId = nil
        steps = []
        turnStarted = Date()
        let model = modelLabel
        // One box: the router decides how to handle the request (see Router.swift).
        let route = Router.route(q)
        routeNote = nil
        switch route {
        case .crossLink:
            askedQuestion = ""
            runCrossLink()
            return
        case .bulkImport:
            askedQuestion = ""
            showBulkImport = true
            return
        default: break
        }
        let useAgent = route == .research && (backend == .mlx || backend == .remote)  // the old Research toggle no longer applies
        askTask = Task {
            do {
                let emb = await getEmbedder()
                let llm = try await getLLM()
                busy = "Searching and writing the answer…"
                let t0 = Date()
                var a: Answer
                var escalated = false
                if useAgent, llm is MLXBackend || llm is RemoteBackend {
                    busy = "Researching…"
                    steps.append("Planning: this needs several notes or the tables")
                    a = try await runResearch(q, embedder: emb, llm: llm, prior: prior) { ev in
                        Task { @MainActor in
                            switch ev {
                            case .step(let s): self.steps.append(s); self.busy = Steps.split(s).title + "…"
                            case .stepDetail(let d): self.attachDetail(d)
                            case .sources(let c): self.sources = c
                            case .token(let t): self.answer += t
                            case .resetText: self.answer = ""
                            }
                        }
                    }
                } else {
                    steps.append("Searching your notes" + (prior.isEmpty ? "" : " (with the conversation so far)")
                                 + Steps.sep + "search(\"\(q)\")" + (prior.isEmpty ? "" : "\nwith earlier turns: \(prior.count)"))
                    busy = "Searching your notes…"
                    let raw = TextBox()
                    a = try await ask(q, embedder: emb, llm: llm, prior: prior,
                                      onSources: { hits in Task { @MainActor in self.sources = hits } }) { tok in
                        raw.append(tok)
                        let shown = Thinking.visible(raw.text)
                        Task { @MainActor in
                            self.busy = shown.isEmpty ? (Thinking.on ? "Thinking…" : "Reading what it found…") : "Writing the answer…"
                            self.answer = shown
                        }
                    }
                    let noteCount = Set(a.sources.map(\.relPath)).count
                    if !a.thinking.isEmpty { steps.append("Thinking" + Steps.sep + a.thinking) }
                    steps.append((a.sources.isEmpty ? "Found nothing close enough to answer from"
                                  : "Read \(a.sources.count) passages from \(noteCount) note\(noteCount == 1 ? "" : "s")")
                                 + (a.sources.isEmpty ? "" : Steps.sep + a.sources.enumerated().map { "[\($0.offset + 1)] \($0.element.relPath) › \($0.element.anchor)" }.joined(separator: "\n")))
                    // Found nothing? Look deeper before giving up.
                    if !Task.isCancelled, Router.shouldEscalate(a), llm is MLXBackend || llm is RemoteBackend {
                        escalated = true
                        answer = ""
                        sources = []
                        busy = "Looking deeper…"
                        steps.append("No direct answer: looking deeper (reading notes, checking tables)")
                        a = try await runResearch(q, embedder: emb, llm: llm, prior: prior) { ev in
                            Task { @MainActor in
                                switch ev {
                                case .step(let s): self.steps.append(s); self.busy = Steps.split(s).title + "…"
                                case .stepDetail(let d): self.attachDetail(d)
                                case .sources(let c): self.sources = c
                                case .token(let t): self.answer += t
                                case .resetText: self.answer = ""
                                }
                            }
                        }
                    }
                }
                routeNote = Router.label(useAgent || escalated ? .research : .answer, escalated: escalated)
                answer = a.text
                sources = a.sources
                answerStats = AnswerStats(passages: a.sources.count, tokens: a.stats.outputTokens,
                                          tokPerSec: a.stats.tokPerSec, seconds: Date().timeIntervalSince(t0))
                if !a.badCitations.isEmpty {
                    warning = "The answer cites passages that don't exist: " + a.badCitations.map { "[\($0)]" }.joined(separator: ", ")
                }
                var entry = HistoryEntry(question: q, answer: a.text, model: model, stats: answerStats!, sources: a.sources)
                if Remote.fellBack {
                    steps.append("\(Remote.host) didn't answer, so this Mac's model answered")
                    Remote.fellBack = false
                }
                steps.append(String(format: Task.isCancelled ? "Stopped after %.0f s" : "Done in %.0f s", Date().timeIntervalSince(t0)))
                entry.steps = steps
                entry.conversationId = convo
                entry.route = routeNote
                history.insert(entry, at: 0)
                currentHistoryId = entry.id
                History.save(history)
            } catch {
                self.error = "\(error)"
            }
            busy = nil
        }
    }

    func askSuggested(_ q: String) {
        question = q
        runAsk()
    }

    // MARK: history

    func openHistory(_ e: HistoryEntry) {
        // While an answer is being written, read the other conversation in its own window
        // instead of replacing the one in progress.
        guard busy == nil else { reading = ThreadRef(id: e.thread); return }
        // The whole conversation: earlier turns above, its latest turn live, ready for a follow-up.
        let thread = history.filter { $0.thread == e.thread }.sorted { $0.date < $1.date }
        let last = thread.last ?? e
        turns = Array(thread.dropLast())
        conversationId = e.thread
        routeNote = last.route
        openTurn(last)
    }

    private func openTurn(_ e: HistoryEntry) {
        askedQuestion = e.question
        answer = e.answer
        sources = e.sources.map(\.chunk)
        steps = e.steps ?? []
        answerStats = e.stats
        warning = nil
        error = nil
        currentHistoryId = e.id
        pane = .ask
    }

    func deleteHistory(_ e: HistoryEntry) {
        history.removeAll { $0.id == e.id }
        History.save(history)
        if currentHistoryId == e.id { newQuestion() }
    }

    func newQuestion() {
        guard busy == nil else { return }
        turns = []
        conversationId = nil
        routeNote = nil
        currentHistoryId = nil
        answer = ""
        sources = []
        steps = []
        answerStats = nil
        warning = nil
        error = nil
        askedQuestion = ""
    }

    func runSearch() {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        Task {
            let emb = await getEmbedder()
            busy = nil
            results = (try? await search(q, embedder: emb, reranker: await Reranker.shared(), limit: 25)) ?? []
        }
    }

    func open(_ c: Chunk) {
        if let n = findNote(c.noteId) ?? notes.first(where: { $0.relPath == c.relPath }) ?? Packs.note(c.relPath) {
            opened = Opened(note: n, anchor: c.anchor)
        }
    }

    func openNote(_ n: Note, anchor: String? = nil) {
        opened = Opened(note: n, anchor: anchor)
    }

    /// Opens a link clicked in a note: `mackb-note:` (a wikilink, resolved like
    /// Obsidian) or `mackb-rel:` (a Markdown link relative to the note). A
    /// wikilink to a note that doesn't exist yet creates it, as Obsidian does.
    func openLink(_ url: URL, from: Note?, newTab: Bool = false) {
        let raw = url.absoluteString
        guard let colon = raw.firstIndex(of: ":") else { return }
        let scheme = raw[..<colon]
        var rest = String(raw[raw.index(after: colon)...])
        var fragment: String?
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: hash)...]).removingPercentEncoding
            rest = String(rest[..<hash])
        }
        let target = rest.removingPercentEncoding ?? rest
        switch scheme {
        case "mackb-note":
            if let n = links.resolve(wikiTarget: target, from: from) {
                openNote(n, anchor: fragment, newTab: newTab)
            } else {
                createNote(named: target, near: from)
            }
        case "mackb-rel":
            let base = (from?.path ?? Config.vault.appendingPathComponent("x")).deletingLastPathComponent()
            let path = URL(fileURLWithPath: target, relativeTo: base).standardizedFileURL.path
            if let n = notes.first(where: { $0.path.standardizedFileURL.path == path }) {
                openNote(n, anchor: fragment, newTab: newTab)
            } else {
                error = "No note at \(target)"
            }
        default:
            NSWorkspace.shared.open(url)
        }
    }

    /// The note a link points to, without opening it (for previews).
    func resolveLink(_ url: URL, from: Note?) -> Opened? {
        let raw = url.absoluteString
        guard let colon = raw.firstIndex(of: ":") else { return nil }
        let scheme = raw[..<colon]
        var rest = String(raw[raw.index(after: colon)...])
        var fragment: String?
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: hash)...]).removingPercentEncoding
            rest = String(rest[..<hash])
        }
        let target = rest.removingPercentEncoding ?? rest
        if scheme == "mackb-note", let n = links.resolve(wikiTarget: target, from: from) { return Opened(note: n, anchor: fragment) }
        if scheme == "mackb-rel" {
            let base = (from?.path ?? Config.vault.appendingPathComponent("x")).deletingLastPathComponent()
            let path = URL(fileURLWithPath: target, relativeTo: base).standardizedFileURL.path
            if let n = notes.first(where: { $0.path.standardizedFileURL.path == path }) { return Opened(note: n, anchor: fragment) }
        }
        return nil
    }

    /// Writes an edited note, refreshes notes and links, and re-indexes it
    /// quietly a few seconds later (so search and Ask see the change).
    func saveNote(at path: URL, text: String) throws {
        if path.standardizedFileURL.path.hasPrefix(Packs.dir.standardizedFileURL.path) {
            throw MacKBError("knowledge packs are read-only")
        }
        Versions.snapshot(path, reason: "edit")
        try text.write(to: path, atomically: true, encoding: .utf8)
        if let fresh = try? Note.read(path) {
            if let i = notes.firstIndex(where: { $0.path == path }) { notes[i] = fresh } else { notes.append(fresh) }
            links = LinkGraph(notes: notes)
            upcoming = Upcoming.scan(notes)
            for i in tabs.indices where tabs[i].opened.note.path == path {
                tabs[i].opened = Opened(note: fresh, anchor: nil)
            }
        }
        reindexTask?.cancel()
        reindexTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, busy == nil else { return }
            let emb = await getEmbedder()
            busy = nil
            try? await reindex(embedder: emb)
            indexCounts = (try? Index().count()) ?? indexCounts
        }
    }

    /// New note: in the given folder, else next to `near`, else the vault
    /// root (in place) or sources/ (managed). Opens it in the editor.
    func createNote(named name: String = "Untitled", in folder: URL? = nil, near: Note? = nil) {
        let dir = folder ?? near?.path.deletingLastPathComponent() ?? (Config.inPlace ? Config.vault : Config.sourcesDir)
        let base = name.replacingOccurrences(of: "/", with: "-")
        var url = dir.appendingPathComponent(base + ".md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base) \(n).md"); n += 1
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "# \(base)\n\n".write(to: url, atomically: true, encoding: .utf8)
            reload()
            if let note = notes.first(where: { $0.path == url }) {
                editing = true
                openNote(note)
            }
        } catch {
            self.error = "Couldn't create \(url.lastPathComponent): \(error)"
        }
    }

    func openSource(_ n: Int) {
        guard n >= 1, n <= sources.count else { return }
        open(sources[n - 1])
    }

    func play(_ note: Note, at seconds: Double) {
        guard let src = note.meta["source"], FileManager.default.fileExists(atPath: src) else { return }
        let url = URL(fileURLWithPath: src)
        if (player.currentItem?.asset as? AVURLAsset)?.url != url {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        player.play()
    }

    // MARK: import

    func importFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose documents, recordings, or a folder of them"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task {
            for u in urls {
                busy = "Importing \(u.lastPathComponent)…"
                do {
                    var isDir: ObjCBool = false
                    FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
                    if isDir.boolValue {
                        _ = try await Task.detached { try ingestFolder(u, tags: []) }.value
                    } else if audioExtensions.contains(u.pathExtension.lowercased()) {
                        busy = "Transcribing \(u.lastPathComponent)…"
                        _ = try await ingestAudio(u, title: nil, tags: [])
                    } else {
                        _ = try await Task.detached { try ingestDocument(u, root: nil, tags: []) }.value
                    }
                } catch {
                    self.error = "\(u.lastPathComponent): \(error)"
                }
            }
            await indexNow()
        }
    }

    func importLink() {
        let link = linkText.trimmingCharacters(in: .whitespaces)
        showLinkSheet = false
        linkText = ""
        guard link.hasPrefix("http") else { return }
        Task {
            busy = "Fetching \(link)…"
            do { _ = try await ingestURL(link, tags: []) } catch { self.error = "\(error)" }
            await indexNow()
        }
    }

    func rebuildIndex() { Task { await indexNow() } }

    // MARK: drop folder

    func revealDrop() {
        Drop.ensure()
        NSWorkspace.shared.activateFileViewerSelecting([Drop.dir])
    }

    /// "Add Files…": pick files; they go through the drop folder like dropped ones.
    func chooseFilesToAdd() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = Config.inPlace
            ? "Choose documents, photos or recordings. The model proposes where each belongs; you approve it in the Inbox."
            : "Choose documents or recordings to import"
        guard panel.runModal() == .OK else { return }
        addToDrop(panel.urls)
    }

    /// Files dropped on the window go into the drop folder, then get filed.
    func addToDrop(_ urls: [URL]) {
        do { try Drop.add(urls) } catch { self.error = "\(error)" }
        fileDropped()
    }

    /// Files whatever is waiting in the drop folder, one at a time, when the
    /// model is free (an answer in progress goes first).
    func fileDropped() {
        guard !filing, busy == nil, !dropPaused else { return }
        let files = Drop.pending()
        guard !files.isEmpty else { queueDone = 0; queueLeft = 0; return }
        filing = true
        Task {
            for u in files {
                if dropPaused { break }
                queueLeft = max(Drop.pending(settled: false).count, 1)
                dropStatus = "Reading \(u.lastPathComponent)…"
                do {
                    let emb = await getEmbedder()
                    let llm: LLMBackend? = Config.inPlace ? try await getLLM() : nil
                    dropStatus = Config.inPlace ? "Deciding where \(u.lastPathComponent) belongs…" : "Importing \(u.lastPathComponent)…"
                    busy = dropStatus
                    _ = try await Drop.process(u, embedder: emb, llm: llm, model: modelLabel)
                } catch let e as AlreadyFiled {
                    dropErrors.append("Skipped \(u.lastPathComponent): \(e)")
                } catch {
                    dropErrors.append("\(u.lastPathComponent): \(error)")
                }
                busy = nil
                queueDone += 1
                queueLeft = Drop.pending(settled: false).count
                if queueDone % 5 == 0, Config.inPlace { inboxItems = inbox() }
            }
            dropStatus = nil
            filing = false
            if queueLeft == 0 { queueDone = 0 }
            if Config.inPlace { reload() } else { await indexNow() }
        }
    }

    private func indexNow() async {
        let emb = await getEmbedder()
        busy = "Indexing…"
        do { try await reindex(embedder: emb) } catch { self.error = "\(error)" }
        busy = nil
        reload()
    }

    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose a vault folder (Markdown notes; can be an Obsidian vault)"
        guard panel.runModal() == .OK, let u = panel.url else { return }
        vault = u
        UserDefaults.standard.set(u.path, forKey: "vault")
        tabs = []
        activeTab = nil
        currentHistoryId = nil
        askedQuestion = ""
        answer = ""
        sources = []
        results = []
        reload()
    }

    // MARK: tabs and note history

    private var activeIndex: Int? { tabs.firstIndex { $0.id == activeTab } }

    /// Opening a different note in a tab (a link, a citation, Quick Open, the
    /// file tree) pushes the one being left onto that tab's Back list.
    private func navigate(to new: Opened?) {
        guard let new else { closeTab(activeTab); return }
        guard let i = activeIndex else { openInNewTab(new); return }
        let old = tabs[i].opened
        if old.note.path != new.note.path {
            tabs[i].back.append(old)
            if tabs[i].back.count > 100 { tabs[i].back.removeFirst() }
            tabs[i].forward.removeAll()
        }
        tabs[i].opened = new
    }

    func openInNewTab(_ o: Opened) {
        let t = NoteTab(opened: o)
        if let i = activeIndex { tabs.insert(t, at: i + 1) } else { tabs.append(t) }
        activeTab = t.id
    }

    func openNote(_ n: Note, anchor: String? = nil, newTab: Bool) {
        if newTab { openInNewTab(Opened(note: n, anchor: anchor)) } else { openNote(n, anchor: anchor) }
    }

    func closeTab(_ id: UUID?) {
        guard let id, let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: i)
        if activeTab == id { activeTab = tabs.isEmpty ? nil : tabs[min(i, tabs.count - 1)].id }
    }

    func closeOtherTabs(_ id: UUID) {
        tabs.removeAll { $0.id != id }
        activeTab = id
    }

    /// ⌃Tab / ⌃⇧Tab.
    func cycleTab(_ step: Int) {
        guard let i = activeIndex, tabs.count > 1 else { return }
        activeTab = tabs[(i + step + tabs.count) % tabs.count].id
    }

    /// The latest copy of a note from history (it may have been edited since).
    private func current(_ o: Opened) -> Opened {
        Opened(note: notes.first { $0.path == o.note.path } ?? o.note, anchor: o.anchor)
    }

    func goBack() {
        guard let i = activeIndex, let prev = tabs[i].back.popLast() else { return }
        tabs[i].forward.append(tabs[i].opened)
        tabs[i].opened = current(prev)
    }

    func goForward() {
        guard let i = activeIndex, let next = tabs[i].forward.popLast() else { return }
        tabs[i].back.append(tabs[i].opened)
        tabs[i].opened = current(next)
    }

    // MARK: inbox

    func approveItem(_ n: Note) {
        do {
            let saved = try approve(n.id)
            if n.meta["kind"] == "filing" { opened = Opened(note: saved, anchor: nil) }
        } catch { self.error = "\(error)" }
        reload()
        rebuildIndex()
    }

    func rejectItem(_ n: Note) {
        do { try reject(n.id) } catch { self.error = "\(error)" }
        reload()
    }

    /// Attaches a tool call's detail to the step just announced.
    func attachDetail(_ d: String) {
        guard let i = steps.indices.last, Steps.split(steps[i]).detail == nil else { return }
        steps[i] += Steps.sep + d
    }

    // MARK: bulk import

    /// Brings files and folders in. `asIs`: copy and convert into `folder` with no
    /// model; otherwise each file goes through the drop folder to be filed.
    func bulkImport(_ urls: [URL], asIs: Bool, folder: String) {
        guard !urls.isEmpty else { return }
        if asIs {
            importProgress = (0, 0, "Opening…")
            Task {
                let report = await BulkImport.asIs(urls, into: folder) { done, total, file in
                    await MainActor.run { self.importProgress = (done, total, file) }
                }
                importProgress = nil
                notice = "Imported \(report.notes) notes and \(report.tables) tables into \(report.folder)/"
                    + (report.skipped.isEmpty ? "." : "; skipped \(report.skipped.count): " + report.skipped.prefix(5).joined(separator: ", "))
                await indexNow()
            }
        } else {
            do {
                let r = try BulkImport.queue(urls)
                queueLeft = Drop.pending(settled: false).count
                notice = "Queued \(r.queued) files to file" + (r.skipped.isEmpty ? "." : "; skipped \(r.skipped.count) of a type Holdfast can't read yet.")
                pane = .inbox
                fileDropped()
            } catch { self.error = "\(error)" }
        }
    }

    func chooseBulkImport() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose files, folders, zip archives or exports (Evernote, Day One, mailboxes)"
        return panel.runModal() == .OK ? panel.urls : []
    }

    func pauseFiling(_ paused: Bool) {
        dropPaused = paused
        if !paused { fileDropped() }
    }

    /// Approves several filings at once; one reload and reindex at the end.
    func approveAll(_ items: [Note]) {
        var failed: [String] = []
        for n in items {
            do { _ = try approve(n.id) } catch { failed.append("\(n.title): \(error)") }
        }
        notice = "Filed \(items.count - failed.count) of \(items.count)."
        if !failed.isEmpty { self.error = failed.joined(separator: "\n") }
        reload()
        rebuildIndex()
    }

    /// The cross-link job: close notes that don't link yet, one yes/no per pair, proposals to the Inbox.
    func runCrossLink() {
        guard importProgress == nil else { return }
        jobTitle = "Checking"
        jobStop = false
        importProgress = (0, 0, "Finding close notes…")
        Task {
            do {
                let llm = try await getLLM()
                busy = "Suggesting links…"
                let model = modelLabel
                let verdicts = await CrossLink.run(llm: llm, model: model) { done, total, label in
                    await MainActor.run {
                        self.importProgress = (done, total, label)
                        if done % 5 == 0 { self.inboxItems = inbox() }
                    }
                    return await MainActor.run { !self.jobStop }
                }
                let yes = verdicts.filter(\.link).count
                notice = "Checked \(verdicts.count) pairs of close notes; proposed \(yes) links."
            } catch { self.error = "\(error)" }
            busy = nil
            importProgress = nil
            jobTitle = "Importing"
            reload()
            pane = .inbox
        }
    }

    func stopJob() { jobStop = true }

    /// Builds a knowledge pack's search index (minutes for a whole Bible).
    func indexPack(_ id: String) {
        Task {
            let emb = await getEmbedder()
            busy = "Indexing the \(Packs.manifest(id)?.name ?? id) pack…"
            do { try await Packs.reindex(id, embedder: emb) } catch { self.error = "\(error)" }
            busy = nil
            indexCounts = (try? Index().count()) ?? indexCounts
            notice = "Indexed the \(Packs.manifest(id)?.name ?? id) pack."
        }
    }

    // MARK: keeping

    func undoFiling(_ r: FilingRecord) {
        do { notice = try FilingLog.undo(r.id) } catch { self.error = "\(error)" }
        reload()
        rebuildIndex()
    }

    func restore(_ v: Versions.Version, of note: Note) {
        do {
            try Versions.restore(v, to: note.path)
            notice = "Restored \(note.title) to the copy from \(v.date.formatted(date: .abbreviated, time: .shortened))."
        } catch { self.error = "\(error)" }
        reload()
        rebuildIndex()
    }

    func complete(_ f: FollowUp) {
        do { try Upcoming.complete(f) } catch { self.error = "\(error)" }
        reload()
    }

    func acceptRule(_ c: Rules.Candidate, auto: Bool) {
        do {
            try Rules.add(FilingRule(match: c.from, target: c.target, action: c.action, auto: auto))
            notice = "New rule: documents from \(c.from) go to \(c.target)\(auto ? ", filed automatically" : "")."
        } catch { self.error = "\(error)" }
        reload()
    }

    func dismissRule(_ c: Rules.Candidate) {
        Rules.dismiss(c)
        reload()
    }

    /// The rules file, opened in the editor (it lives with the app's state, not in the vault).
    func openRules() {
        if !FileManager.default.fileExists(atPath: Rules.url.path) {
            try? FileManager.default.createDirectory(at: Rules.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? (Rules.header + "\n").write(to: Rules.url, atomically: true, encoding: .utf8)
        }
        if let n = try? Note.read(Rules.url) { openNote(n, newTab: true) }
    }
}

