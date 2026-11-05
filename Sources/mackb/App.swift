import AppKit
import AVFoundation
import SwiftUI

// MARK: - App

struct MacKBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup("MacKB") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 1080, minHeight: 660)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Vault") {
                Button("Import Files or Folder…") { store.importFiles() }.keyboardShortcut("i")
                Button("Add Link…") { store.showLinkSheet = true }.keyboardShortcut("l")
                Button("Rebuild Index") { store.rebuildIndex() }
                Divider()
                Button("Choose Vault…") { store.chooseVault() }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // A bare executable needs this to get a Dock icon and keyboard focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

enum Pane: String, CaseIterable, Identifiable {
    case ask = "Ask", library = "Library", inbox = "Inbox"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .ask: return "bubble.left.and.text.bubble.right"
        case .library: return "books.vertical"
        case .inbox: return "tray"
        }
    }
}

enum Backend: String, CaseIterable, Identifiable {
    case mlx = "Qwen 3.8 27B · MLX (in app)"
    case ollama = "Qwen 3.8 27B · Ollama"
    var id: String { rawValue }
}

struct Opened: Equatable {
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
    @Published var stats = ""
    @Published var busy: String?
    @Published var error: String?
    @Published var opened: Opened?
    @Published var searchText = ""
    @Published var results: [Chunk] = []
    @Published var backend: Backend = .mlx
    @Published var showLinkSheet = false
    @Published var linkText = ""
    @Published var indexCounts = (chunks: 0, notes: 0, vectors: 0)

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
    }

    func reload() {
        Config.vaultOverride = vault
        try? ensureVault()
        notes = allNotes()
        inboxItems = inbox()
        indexCounts = (try? Index().count()) ?? (0, 0, 0)
    }

    private func getEmbedder() async -> Embedder? {
        if embedder == nil {
            busy = "Loading the embedding model…"
            embedder = try? await Embedder.load()
        }
        return embedder
    }

    private func getLLM() async throws -> LLMBackend {
        UserDefaults.standard.set(backend.rawValue, forKey: "backend")
        switch backend {
        case .ollama: return OllamaBackend()
        case .mlx:
            busy = "Loading Qwen 3.8 27B into memory (first question only)…"
            return try await MLXBackend.shared()
        }
    }

    func runAsk() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, busy == nil else { return }
        answer = ""
        sources = []
        stats = ""
        error = nil
        Task {
            do {
                let emb = await getEmbedder()
                let llm = try await getLLM()
                busy = "Searching and writing the answer…"
                let t0 = Date()
                let a = try await ask(q, embedder: emb, llm: llm) { tok in
                    Task { @MainActor in self.answer += tok }
                }
                answer = a.text
                sources = a.sources
                stats = String(format: "%d passages · %d tokens at %.1f tok/s · %.0fs",
                               a.sources.count, a.stats.outputTokens, a.stats.tokPerSec, Date().timeIntervalSince(t0))
            } catch {
                self.error = "\(error)"
            }
            busy = nil
        }
    }

    func runSearch() {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        Task {
            let emb = await getEmbedder()
            busy = nil
            results = (try? await search(q, embedder: emb, limit: 25)) ?? []
        }
    }

    func open(_ c: Chunk) {
        if let n = findNote(c.noteId) ?? notes.first(where: { $0.relPath == c.relPath }) {
            opened = Opened(note: n, anchor: c.anchor)
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
        opened = nil
        answer = ""
        sources = []
        results = []
        reload()
    }

    // MARK: inbox

    func approveItem(_ n: Note) {
        do { _ = try approve(n.id) } catch { self.error = "\(error)" }
        reload()
        rebuildIndex()
    }

    func rejectItem(_ n: Note) {
        do { try reject(n.id) } catch { self.error = "\(error)" }
        reload()
    }
}

// MARK: - Views

struct RootView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationSplitView {
            List(selection: $store.pane) {
                ForEach(Pane.allCases) { p in
                    Label(p.rawValue, systemImage: p.icon)
                        .badge(p == .inbox ? store.inboxItems.count : 0)
                        .tag(p)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
            .safeAreaInset(edge: .bottom) { VaultFooter() }
        } content: {
            Group {
                switch store.pane ?? .ask {
                case .ask: AskView()
                case .library: LibraryView()
                case .inbox: InboxView()
                }
            }
            .navigationSplitViewColumnWidth(min: 420, ideal: 520)
        } detail: {
            if let o = store.opened {
                NoteView(opened: o)
            } else {
                ContentUnavailableView("No note open", systemImage: "doc.text",
                                       description: Text("Click a citation or a note to read it here."))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { store.importFiles() } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    .help("Import documents, recordings, or a folder")
                Button { store.showLinkSheet = true } label: { Label("Add Link", systemImage: "link.badge.plus") }
                    .help("Import a YouTube or podcast link")
            }
        }
        .sheet(isPresented: $store.showLinkSheet) { LinkSheet() }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "mackb", let n = Int(url.lastPathComponent) {
                store.openSource(n)
                return .handled
            }
            return .systemAction
        })
    }
}

struct VaultFooter: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let b = store.busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(b).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Button { store.chooseVault() } label: {
                Label(store.vault.lastPathComponent, systemImage: "folder")
            }
            .buttonStyle(.plain)
            .help(store.vault.path)
            Text("\(store.notes.count) notes · \(store.indexCounts.chunks) passages")
                .font(.caption2).foregroundStyle(.secondary)
            Label("Everything stays on this Mac", systemImage: "lock")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AskView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                TextField("Ask a question of your materials and case reports…", text: $store.question, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .onSubmit { store.runAsk() }
                Button("Ask") { store.runAsk() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(store.busy != nil || store.question.isEmpty)
            }
            Picker("Model", selection: $store.backend) {
                ForEach(Backend.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 320)

            if let b = store.busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(b).foregroundStyle(.secondary)
                }
            }
            if let e = store.error {
                Text(e).foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.answer.isEmpty && store.busy == nil {
                        Text("Answers come only from the notes in this vault, and every claim cites its source. Click a [number] to open the passage.")
                            .foregroundStyle(.secondary)
                    }
                    if !store.answer.isEmpty {
                        MarkdownBlocks(text: store.answer, linkCitations: true)
                    }
                    if !store.stats.isEmpty {
                        Text(store.stats).font(.caption).foregroundStyle(.secondary)
                    }
                    if !store.sources.isEmpty {
                        Divider()
                        Text("Sources").font(.headline)
                        ForEach(Array(store.sources.enumerated()), id: \.offset) { i, c in
                            SourceRow(n: i + 1, chunk: c)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
        }
        .padding()
        .navigationTitle("Ask")
    }
}

struct SourceRow: View {
    @EnvironmentObject var store: Store
    var n: Int?
    var chunk: Chunk

    var body: some View {
        Button { store.open(chunk) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let n { Text("[\(n)]").monospacedDigit().foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(chunk.title).fontWeight(.medium)
                    if chunk.anchor != chunk.title {
                        Text(chunk.anchor).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(chunk.text.split(separator: "\n").dropFirst().joined(separator: " "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LibraryView: View {
    @EnvironmentObject var store: Store

    var grouped: [(String, [Note])] {
        let kinds = Dictionary(grouping: store.notes) { $0.meta["kind"] ?? "document" }
        let order = ["memory": "Approved memories", "recording": "Recordings", "video": "Videos", "document": "Documents"]
        return order.compactMap { k, label in kinds[k].map { (label, $0) } }.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search the vault (keywords and meaning)…", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { store.runSearch() }
                .padding()
            List {
                if !store.searchText.isEmpty && !store.results.isEmpty {
                    Section("Results") {
                        ForEach(Array(store.results.enumerated()), id: \.offset) { _, c in SourceRow(chunk: c) }
                    }
                } else {
                    ForEach(grouped, id: \.0) { label, notes in
                        Section("\(label) (\(notes.count))") {
                            ForEach(notes, id: \.path) { n in
                                Button { store.opened = Opened(note: n, anchor: nil) } label: {
                                    VStack(alignment: .leading) {
                                        Text(n.title)
                                        if let t = n.meta["tags"] { Text(t).font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Library")
    }
}

struct InboxView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Group {
            if store.inboxItems.isEmpty {
                ContentUnavailableView("Inbox is empty", systemImage: "tray",
                                       description: Text("Memories that agents (like Claude Code over MCP) propose to save wait here for your approval."))
            } else {
                List(store.inboxItems, id: \.path) { n in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(n.title).font(.headline)
                        Text("Proposed by \(n.meta["proposed_by"] ?? "?") · \(n.meta["proposed"] ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                        if let f = n.meta["privacy_flags"] {
                            Label(f, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        Text(n.body.split(separator: "\n").filter { !$0.hasPrefix("#") }.joined(separator: " "))
                            .lineLimit(4)
                        HStack {
                            Button("Approve") { store.approveItem(n) }.buttonStyle(.borderedProminent)
                            Button("Reject") { store.rejectItem(n) }
                            Button("Open") { store.opened = Opened(note: n, anchor: nil) }.buttonStyle(.link)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Inbox")
    }
}

struct LinkSheet: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add a link").font(.headline)
            Text("YouTube or another video/podcast page. Captions are used when available; otherwise the audio is transcribed on this Mac.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("https://…", text: $store.linkText).textFieldStyle(.roundedBorder).frame(width: 420)
            HStack {
                Spacer()
                Button("Cancel") { store.showLinkSheet = false }
                Button("Import") { store.importLink() }.buttonStyle(.borderedProminent).keyboardShortcut(.return)
            }
        }
        .padding(20)
    }
}

// MARK: - Note viewer

struct NoteView: View {
    @EnvironmentObject var store: Store
    var opened: Opened

    struct Block: Identifiable {
        var id: Int
        var text: String
        var level: Int  // 0 = body, 1-3 = heading
        var time: Double?
    }

    var blocks: [Block] {
        var out: [Block] = []
        for line in opened.note.body.split(separator: "\n").map(String.init) where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            var level = 0
            var text = line
            if line.hasPrefix("#") {
                level = min(line.prefix(while: { $0 == "#" }).count, 3)
                text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
            }
            var time: Double?
            if line.hasPrefix("["), line.count > 10, line.dropFirst(9).first == "]" { time = parseTime(String(line.dropFirst().prefix(8))) }
            if line.hasPrefix("**"), line.count > 12 { time = parseTime(String(line.dropFirst(2).prefix(8))) }
            out.append(Block(id: out.count, text: text, level: level, time: time))
        }
        return out
    }

    func isAnchor(_ b: Block) -> Bool {
        guard let a = opened.anchor, a != opened.note.title else { return false }
        return (b.level > 0 && b.text == a) || b.text.hasPrefix("[\(a)]") || b.text.hasPrefix("**\(a)**")
    }

    var isRecording: Bool {
        guard let src = opened.note.meta["source"] else { return false }
        return ["recording", "video"].contains(opened.note.meta["kind"] ?? "") && FileManager.default.fileExists(atPath: src)
    }

    var body: some View {
        let bs = blocks
        let anchorIdx = bs.firstIndex(where: isAnchor)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        if let k = opened.note.meta["kind"] { Text(k.capitalized).font(.caption).padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule()) }
                        if let t = opened.note.meta["tags"] { Text(t).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([opened.note.path]) }
                            .buttonStyle(.link).font(.caption)
                    }
                    ForEach(bs) { b in
                        let inAnchor = anchorIdx.map { i in b.id == i || (bs[i].level > 0 && b.id > i && !bs[(i + 1)...b.id].contains { $0.level > 0 }) } ?? false
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if let t = b.time, isRecording {
                                Button { store.play(opened.note, at: t) } label: { Image(systemName: "play.circle") }
                                    .buttonStyle(.plain).help("Play from here")
                            }
                            blockText(b)
                        }
                        .padding(.vertical, inAnchor ? 3 : 0)
                        .padding(.horizontal, inAnchor ? 6 : 0)
                        .background(inAnchor ? Color.yellow.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .id(b.id)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .onAppear { if let i = anchorIdx { proxy.scrollTo(i, anchor: .top) } }
            .onChange(of: opened) { _, _ in
                if let i = blocks.firstIndex(where: isAnchor) { withAnimation { proxy.scrollTo(i, anchor: .top) } }
                else { proxy.scrollTo(0, anchor: .top) }
            }
        }
        .navigationTitle(opened.note.title)
    }

    @ViewBuilder func blockText(_ b: Block) -> some View {
        switch b.level {
        case 1: Text(b.text).font(.title2.bold()).padding(.top, 4)
        case 2: Text(b.text).font(.headline).padding(.top, 10)
        case 3: Text(b.text).font(.subheadline.bold()).padding(.top, 6)
        default: Text(inlineMarkdown(b.text))
        }
    }
}

// MARK: - Markdown rendering (enough for answers and notes)

func inlineMarkdown(_ s: String, linkCitations: Bool = false) -> AttributedString {
    var md = s
    if linkCitations {
        md = md.replacingOccurrences(of: #"\[(\d+)\]"#, with: "[[$1]](mackb://cite/$1)", options: .regularExpression)
    }
    return (try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
}

struct MarkdownBlocks: View {
    var text: String
    var linkCitations = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: true).enumerated()), id: \.offset) { _, raw in
                let line = String(raw)
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    Text(inlineMarkdown(trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces), linkCitations: linkCitations))
                        .font(.headline).padding(.top, 6)
                } else if let r = trimmed.range(of: #"^([*\-•]|\d+\.)\s+"#, options: .regularExpression) {
                    let marker = trimmed[r].trimmingCharacters(in: .whitespaces)
                    let indent = line.prefix(while: { $0 == " " }).count >= 2
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker.first?.isNumber == true ? marker : "•").foregroundStyle(.secondary)
                        Text(inlineMarkdown(String(trimmed[r.upperBound...]), linkCitations: linkCitations))
                    }
                    .padding(.leading, indent ? 18 : 0)
                } else {
                    Text(inlineMarkdown(trimmed, linkCitations: linkCitations))
                }
            }
        }
    }
}
