import AppKit
import SwiftUI

// MARK: - Design system

/// One accent (an obsidian-violet), cards on a soft canvas, and a colour per
/// kind of note. Light and dark mode both come from system colours.
enum Theme {
    static let accent = Color(red: 0.40, green: 0.33, blue: 0.88)
    static let accent2 = Color(red: 0.62, green: 0.36, blue: 0.93)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let radius: CGFloat = 12

    static func kind(of n: Note) -> String {
        n.meta["doc_type"] == "case-report" ? "case-report" : (n.meta["kind"] ?? "document")
    }
    static func icon(_ kind: String) -> String {
        switch kind {
        case "case-report": return "person.text.rectangle"
        case "recording": return "waveform"
        case "video": return "play.rectangle"
        case "memory": return "sparkles"
        default: return "doc.text"
        }
    }
    static func color(_ kind: String) -> Color {
        switch kind {
        case "case-report": return .teal
        case "recording": return .orange
        case "video": return .pink
        case "memory": return accent
        default: return .blue
        }
    }
    static func label(_ kind: String) -> String {
        switch kind {
        case "case-report": return "Case reports"
        case "recording": return "Recordings"
        case "video": return "Videos"
        case "memory": return "Memories"
        default: return "Documents"
        }
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(Theme.card))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(highlighted ? Theme.accent.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: highlighted ? 1.5 : 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
}

extension View {
    func card(padding: CGFloat = 16, highlighted: Bool = false) -> some View {
        modifier(CardStyle(padding: padding, highlighted: highlighted))
    }
}

/// Rounded square with the kind's colour and icon.
struct KindTile: View {
    var kind: String
    var size: CGFloat = 30
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Theme.color(kind).opacity(0.15))
            .frame(width: size, height: size)
            .overlay(Image(systemName: Theme.icon(kind)).font(.system(size: size * 0.46, weight: .medium)).foregroundStyle(Theme.color(kind)))
    }
}

struct Pill: View {
    var text: String
    var icon: String?
    var color: Color = .secondary
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}

struct AppMark: View {
    var size: CGFloat = 30
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(Theme.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: "diamond.fill").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white.opacity(0.95)))
            .shadow(color: Theme.accent.opacity(0.35), radius: size * 0.12, y: size * 0.05)
    }
}

/// Dock icon, drawn at launch (the bundle has no asset catalog).
@MainActor func renderAppIcon() -> NSImage? {
    let view = ZStack {
        RoundedRectangle(cornerRadius: 230, style: .continuous).fill(Theme.gradient).frame(width: 824, height: 824)
        Image(systemName: "diamond.fill").font(.system(size: 360, weight: .semibold)).foregroundStyle(.white.opacity(0.95))
    }
    .frame(width: 1024, height: 1024)
    let r = ImageRenderer(content: view)
    r.scale = 1
    return r.nsImage
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var store: Store
    /// Width of the pane beside a note; drag the divider to change it.
    @AppStorage("listWidth") private var listWidth: Double = 540

    @ViewBuilder var paneView: some View {
        switch store.pane ?? .ask {
        case .ask: AskView()
        case .library: LibraryView()
        case .inbox: InboxView()
        case .history: HistoryView()
        case .files: FilesView()
        case .graph: GraphView()
        }
    }

    var body: some View {
        // Two columns: the sidebar, then the pane and the note side by side in a
        // split view, so the pane (the file list) can be hidden on its own.
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            HStack(spacing: 0) {
                if store.opened == nil && store.pane != .ask && store.pane != nil {
                    paneView.background(Theme.canvas)  // nothing open: the pane gets the room
                } else {
                    if store.showList {
                        paneView
                            .background(Theme.canvas)
                            .frame(width: listWidth)
                        ResizeHandle(width: $listWidth)
                    }
                    if let o = store.opened {
                        VStack(spacing: 0) {
                            TabBar()
                            NoteView(opened: o)
                        }
                        .frame(minWidth: 420, maxWidth: .infinity)
                    } else {
                        EmptyState(icon: "doc.text.magnifyingglass", title: "Nothing open",
                                   message: "Click a citation, a source or a note to read it here.")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .animation(.easeOut(duration: 0.18), value: store.showList)
        }
        .tint(Theme.accent)
        .toolbar {
            ToolbarItemGroup {
                Button { store.importFiles() } label: { Label("Import", systemImage: "square.and.arrow.down") }
                    .help("Import documents, recordings, or a folder (⌘I)")
                Button { store.showLinkSheet = true } label: { Label("Add Link", systemImage: "link.badge.plus") }
                    .help("Import a YouTube or podcast link (⌘L)")
            }
        }
        .sheet(isPresented: $store.showLinkSheet) { LinkSheet() }
        .sheet(isPresented: $store.showQuickOpen) { QuickOpen().environmentObject(store) }
        .sheet(isPresented: $store.showPalette) { CommandPalette().environmentObject(store) }
        .sheet(item: $store.preview) { o in
            NotePreview(opened: o).environmentObject(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Notes may have changed outside the app (Obsidian, Claude Code, git pull).
            if !store.editing { store.reload() }
        }
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "mackb", let n = Int(url.lastPathComponent) {
                store.openSource(n)
                return .handled
            }
            if url.scheme == "mackb-note" || url.scheme == "mackb-rel" {
                let mods = NSEvent.modifierFlags
                if mods.contains(.option) {  // ⌥-click: preview without leaving
                    store.preview = store.resolveLink(url, from: store.opened?.note)
                } else {
                    store.openLink(url, from: store.opened?.note, newTab: mods.contains(.command))
                }
                return .handled
            }
            return .systemAction
        })
    }
}

struct EmptyState: View {
    var icon: String
    var title: String
    var message: String
    var body: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(Theme.accent.opacity(0.1))
                .frame(width: 76, height: 76)
                .overlay(Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(Theme.gradient))
            Text(title).font(.title3.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var store: Store

    var body: some View {
        List(selection: $store.pane) {
            Section {
                ForEach(Pane.allCases) { p in
                    Label(p.rawValue, systemImage: p.icon)
                        .badge(p == .inbox ? store.inboxItems.count : 0)
                        .tag(p)
                }
            } header: {
                HStack(spacing: 10) {
                    AppMark(size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MacKB").font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                        Text("A private second brain").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                .textCase(nil)
                .padding(.bottom, 12)
                .padding(.top, 4)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { VaultCard().padding(10) }
    }
}

struct VaultCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let b = store.busy, store.pane != .ask {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(b).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Divider()
            }
            Button { store.chooseVault() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                    Text(store.vault.lastPathComponent).font(.callout.weight(.medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(store.vault.path) — click to choose another vault")
            HStack(spacing: 12) {
                Label("\(store.notes.count)", systemImage: "doc.on.doc").help("Notes")
                Label("\(store.indexCounts.chunks)", systemImage: "text.alignleft").help("Indexed passages")
            }
            .font(.caption).foregroundStyle(.secondary).labelStyle(TightLabel())
            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                Text("Stays on this Mac")
            }
            .font(.caption2.weight(.medium)).foregroundStyle(.green)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon; configuration.title }
    }
}

// MARK: - Ask

struct AskView: View {
    @EnvironmentObject var store: Store

    var hasConversation: Bool { !store.askedQuestion.isEmpty || store.error != nil }

    var body: some View {
        VStack(spacing: 0) {
            if hasConversation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        QuestionHeader(text: store.askedQuestion)
                        if let b = store.busy { StatusPill(text: b) }
                        if let e = store.error { ErrorBanner(text: e) }
                        if !store.answer.isEmpty || !store.steps.isEmpty { AnswerCard() }
                        if !store.sources.isEmpty { SourcesSection() }
                    }
                    .padding(24)
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            } else {
                AskHero()
            }
            Composer()
                .padding(.horizontal, 20).padding(.bottom, 16).padding(.top, 8)
                .frame(maxWidth: 860)
        }
        .navigationTitle("Ask")
        .toolbar {
            if hasConversation {
                ToolbarItem {
                    Button { store.newQuestion() } label: { Label("New Question", systemImage: "square.and.pencil") }
                        .disabled(store.busy != nil)
                        .help("Clear and start a new question (⌘N)")
                        .keyboardShortcut("n")
                }
            }
        }
    }
}

struct AskHero: View {
    @EnvironmentObject var store: Store
    var suggestions: [(String, String)] { store.profile.suggestions.map { ($0.icon, $0.text) } }
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 40)
                AppMark(size: 56)
                VStack(spacing: 6) {
                    Text(store.profile == .counseling ? "Ask your case notes" : "Ask your knowledge base")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                    Text("Answers come only from the notes in this vault, and every claim cites its source.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                AddFilesCard()
                    .frame(maxWidth: 560)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                    ForEach(suggestions, id: \.1) { icon, q in SuggestionCard(icon: icon, text: q) { store.askSuggested(q) } }
                }
                .frame(maxWidth: 560)
                if !store.history.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("RECENT").font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
                            Spacer()
                            Button("See all") { store.pane = .history }.buttonStyle(.link).font(.caption)
                        }
                        ForEach(store.history.prefix(3)) { e in
                            Button { store.openHistory(e) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary).font(.caption)
                                    Text(e.question).font(.callout).lineLimit(1).foregroundStyle(.primary)
                                    Spacer()
                                    Text(e.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 4).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 560)
                    .padding(.top, 6)
                }
                Spacer(minLength: 20)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}

/// On the Ask page: add files to the vault (via the drop folder), or drop them here.
struct AddFilesCard: View {
    @EnvironmentObject var store: Store
    @State private var targeted = false

    var waiting: Int { store.inboxItems.filter { $0.meta["kind"] == "filing" }.count }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: store.dropStatus == nil ? "tray.and.arrow.down.fill" : "gearshape.2.fill")
                .font(.system(size: 20)).foregroundStyle(Theme.accent)
                .symbolEffect(.pulse, isActive: store.dropStatus != nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.dropStatus ?? "Add files to your knowledge base").font(.callout.weight(.semibold))
                Text(Config.inPlace ? "Drop documents, photos or recordings here; the model proposes where each belongs."
                                    : "Drop documents or recordings here to import them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if waiting > 0 {
                Button("\(waiting) to review") { store.pane = .inbox }.buttonStyle(.link).font(.caption)
            }
            Button("Add Files…") { store.chooseFilesToAdd() }.buttonStyle(.borderedProminent).controlSize(.regular)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(targeted ? 0.14 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Theme.accent.opacity(targeted ? 0.9 : 0.3), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4])))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in store.addToDrop([url]) } }
                }
            }
            return true
        }
    }
}

struct SuggestionCard: View {
    var icon: String
    var text: String
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 18)
                Text(text).font(.callout).multilineTextAlignment(.leading).foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
            .card(padding: 12, highlighted: hover)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct QuestionHeader: View {
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.secondary)
            Text(text).font(.title3.weight(.semibold)).textSelection(.enabled)
        }
    }
}

struct StatusPill: View {
    var text: String
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Theme.accent.opacity(0.09)))
    }
}

struct ErrorBanner: View {
    var text: String
    var color: Color = .red
    var icon = "exclamationmark.octagon.fill"
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.callout).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.1)))
    }
}

struct AnswerCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Theme.gradient)
                Text("Answer").font(.headline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.answer, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless).help("Copy the answer")
                .disabled(store.busy != nil)
            }
            // No .textSelection here: on macOS it routes link clicks around
            // the openURL handler, so citations wouldn't open. Copy is above.
            if !store.steps.isEmpty { StepsList(steps: store.steps, running: store.busy != nil) }
            MarkdownBlocks(text: store.answer, linkCitations: true)
            if let w = store.warning {
                ErrorBanner(text: w, color: .orange, icon: "exclamationmark.triangle.fill")
            }
            if let s = store.answerStats {
                Divider()
                HStack(spacing: 14) {
                    Label("\(s.passages) passages", systemImage: "text.quote")
                    Label("\(s.tokens) tokens", systemImage: "number")
                    Label(String(format: "%.1f tok/s", s.tokPerSec), systemImage: "gauge.with.dots.needle.67percent")
                    Label(String(format: "%.0f s", s.seconds), systemImage: "clock")
                    Spacer()
                    Label(store.history.first { $0.id == store.currentHistoryId }?.model ?? store.modelLabel, systemImage: "cpu")
                }
                .labelStyle(TightLabel())
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card(padding: 20)
    }
}

struct SourcesSection: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sources").font(.headline)
                Text("\(store.sources.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(.quaternary))
            }
            ForEach(Array(store.sources.enumerated()), id: \.offset) { i, c in
                SourceCard(n: i + 1, chunk: c)
            }
        }
    }
}

struct SourceCard: View {
    @EnvironmentObject var store: Store
    var n: Int?
    var chunk: Chunk
    @State private var hover = false

    var isOpen: Bool { store.opened?.note.relPath == chunk.relPath && store.opened?.anchor == chunk.anchor }
    var kind: String { store.notes.first { $0.id == chunk.noteId }.map(Theme.kind(of:)) ?? "document" }
    var snippet: String {
        chunk.text.split(separator: "\n").dropFirst().joined(separator: " ")
            .replacingOccurrences(of: #"#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Button { store.open(chunk) } label: {
            HStack(alignment: .top, spacing: 12) {
                if let n {
                    Text("\(n)")
                        .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.accent)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.accent.opacity(0.12)))
                } else {
                    KindTile(kind: kind, size: 26)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(chunk.title).font(.callout.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        if let s = chunk.score { RelevanceMeter(score: s) }
                    }
                    if chunk.anchor != chunk.title {
                        Text(chunk.anchor).font(.caption.weight(.medium)).foregroundStyle(Theme.accent).lineLimit(1)
                    }
                    if !snippet.isEmpty {
                        Text(snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 12, highlighted: hover || isOpen)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

struct RelevanceMeter: View {
    var score: Double
    var body: some View {
        HStack(spacing: 5) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Theme.gradient).frame(width: max(3, 36 * min(max(score, 0), 1)))
            }
            .frame(width: 36, height: 4)
            Text(String(format: "%.0f%%", score * 100)).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
        }
        .help("Relevance from the reranker")
    }
}

struct Composer: View {
    @EnvironmentObject var store: Store
    @FocusState private var focused: Bool

    var canSend: Bool { store.busy == nil && !store.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(store.profile == .counseling ? "Ask about your materials and case reports…" : "Ask your knowledge base…", text: $store.question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...6)
                    .focused($focused)
                    .onSubmit { store.runAsk() }
                    .padding(.vertical, 5)
                Button { store.runAsk() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(canSend ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.secondary.opacity(0.35))))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend)
                .help("Ask (Return)")
            }
            .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(focused ? Theme.accent.opacity(0.55) : Color.primary.opacity(0.1), lineWidth: focused ? 1.5 : 1))
            .shadow(color: .black.opacity(focused ? 0.1 : 0.06), radius: 12, y: 3)
            .animation(.easeOut(duration: 0.15), value: focused)

            HStack {
                Menu {
                    Section("On this Mac (MLX)") {
                        ForEach(MLXModelSpec.shortList.filter { store.isDownloaded($0.repo) }) { spec in
                            Toggle("\(spec.name) · \(spec.detail)", isOn: Binding(
                                get: { store.backend == .mlx && store.mlxRepo == spec.repo },
                                set: { if $0 { store.selectMLX(spec.repo) } }))
                        }
                    }
                    Section("Ollama") {
                        Toggle("Qwen 3.8 27B · 8-bit", isOn: Binding(
                            get: { store.backend == .ollama },
                            set: { if $0 { store.backend = .ollama } }))
                    }
                    Divider()
                    SettingsLink { Text("More Models…") }
                } label: {
                    Label(store.modelLabel, systemImage: "cpu")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(.caption)
                Toggle(isOn: $store.research) {
                    Label("Research", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .disabled(store.backend != .mlx)
                .help("Research mode: the model searches, reads notes, lists folders and queries CSV tables in steps before answering. Slower, better for questions that span files or need numbers. MLX models only.")
                Button { store.chooseFilesToAdd() } label: {
                    Label("Add Files", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(Config.inPlace
                      ? "Add documents, photos or recordings. The model proposes where each belongs; you approve it in the Inbox."
                      : "Add documents or recordings to the vault as sources.")
                Spacer()
                Label("Private · nothing leaves this Mac", systemImage: "lock.fill")
                    .labelStyle(TightLabel())
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
        }
        .onAppear { focused = true }
    }
}

// MARK: - Library

struct LibraryView: View {
    @EnvironmentObject var store: Store
    @State private var filter: String?

    var kinds: [String] {
        let present = Set(store.notes.map(Theme.kind(of:)))
        return ["case-report", "document", "recording", "video", "memory"].filter(present.contains)
    }

    var grouped: [(String, [Note])] {
        let byKind = Dictionary(grouping: store.notes, by: Theme.kind(of:))
        return kinds.filter { filter == nil || $0 == filter }.compactMap { k in
            byKind[k].map { (k, $0.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) }
        }
    }

    var searching: Bool { !store.searchText.isEmpty && !store.results.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                SearchField(text: $store.searchText) { store.runSearch() }
                if !searching && kinds.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            FilterChip(title: "All", count: store.notes.count, selected: filter == nil) { filter = nil }
                            ForEach(kinds, id: \.self) { k in
                                FilterChip(title: Theme.label(k), count: store.notes.filter { Theme.kind(of: $0) == k }.count,
                                           icon: Theme.icon(k), selected: filter == k) { filter = filter == k ? nil : k }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 10)

            if store.notes.isEmpty {
                EmptyState(icon: "books.vertical", title: "Your library is empty",
                           message: "Import documents, recordings or a folder with ⌘I, or add a link with ⌘L.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8, pinnedViews: []) {
                        if searching {
                            SectionTitle(title: "Results", count: store.results.count)
                            ForEach(Array(store.results.enumerated()), id: \.offset) { _, c in SourceCard(chunk: c) }
                        } else {
                            ForEach(grouped, id: \.0) { kind, notes in
                                SectionTitle(title: Theme.label(kind), count: notes.count)
                                ForEach(notes, id: \.path) { n in NoteRow(note: n) }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("Library")
    }
}

struct SectionTitle: View {
    var title: String
    var count: Int
    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
            Text("\(count)").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.top, 12).padding(.bottom, 2).padding(.leading, 4)
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder = "Search by keyword or meaning…"
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(focused ? Theme.accent.opacity(0.55) : Color.primary.opacity(0.1), lineWidth: focused ? 1.5 : 1))
    }
}

struct FilterChip: View {
    var title: String
    var count: Int
    var icon: String?
    var selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon) }
                Text(title)
                Text("\(count)").foregroundStyle(selected ? .white.opacity(0.75) : .secondary)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(selected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.primary.opacity(0.06))))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct NoteRow: View {
    @EnvironmentObject var store: Store
    var note: Note
    @State private var hover = false

    var subtitle: String {
        var parts: [String] = []
        if let c = note.meta["case"] { parts.append(c) }
        if let s = note.meta["session"] { parts.append("Session \(s)") }
        if let k = note.meta["session_kind"] { parts.append(k) }
        if let d = note.meta["date"] ?? note.meta["created"] { parts.append(String(d.prefix(10))) }
        if let t = note.meta["tags"], !t.isEmpty, t != note.meta["doc_type"] { parts.append(t) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let selected = store.opened?.note.path == note.path
        Button { store.opened = Opened(note: note, anchor: nil) } label: {
            HStack(spacing: 12) {
                KindTile(kind: Theme.kind(of: note), size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title).font(.callout.weight(.medium)).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .opacity(hover || selected ? 1 : 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.12) : (hover ? Color.primary.opacity(0.05) : Theme.card)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Theme.accent.opacity(0.45) : Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Inbox

struct InboxView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                DropZone()
                if store.inboxItems.isEmpty {
                    EmptyState(icon: "tray", title: "All caught up",
                               message: Config.inPlace
                               ? "Files you drop are read by the model, which proposes where each belongs. Proposals, and memories agents ask to save, wait here for your approval."
                               : "Memories that agents (like Claude Code over MCP) propose to save wait here for your approval.")
                        .frame(minHeight: 260)
                } else {
                    Text("Nothing is written until you approve.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach(store.inboxItems, id: \.path) { n in InboxCard(note: n) }
                }
            }
            .padding(20)
        }
        .navigationTitle("Inbox")
    }
}

/// Drop files here, or into the drop folder in Finder; the app files them.
struct DropZone: View {
    @EnvironmentObject var store: Store
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: store.dropStatus == nil ? "tray.and.arrow.down.fill" : "gearshape.2.fill")
                    .font(.system(size: 26)).foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse, isActive: store.dropStatus != nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.dropStatus ?? "Drop files to add them to the vault").font(.headline)
                    Text(Config.inPlace
                         ? "PDFs, Word, Markdown, images (read on-device), recordings. The model proposes a note or a log entry; you approve it below."
                         : "Documents and recordings are imported as sources and indexed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Drop Folder") { store.revealDrop() }.buttonStyle(.bordered)
            }
            ForEach(store.dropErrors, id: \.self) { e in
                ErrorBanner(text: e, color: .orange, icon: "exclamationmark.triangle.fill")
            }
            if !store.dropErrors.isEmpty {
                Button("Clear") { store.dropErrors = [] }.buttonStyle(.link).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent.opacity(targeted ? 0.14 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Theme.accent.opacity(targeted ? 0.9 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in store.addToDrop([url]) } }
                }
            }
            return true
        }
    }
}

struct InboxCard: View {
    @EnvironmentObject var store: Store
    var note: Note

    var isFiling: Bool { note.meta["kind"] == "filing" }

    var preview: String {
        note.body.split(separator: "\n").filter { !$0.hasPrefix("#") }.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                KindTile(kind: isFiling ? "document" : "memory", size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.title).font(.headline)
                    Text("Proposed by \(note.meta["proposed_by"] ?? "an agent")\(note.meta["proposed"].map { " · \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if isFiling, let target = note.meta["target"] {
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(note.meta["action"] == "append" ? "Append to " : "New note ")
                            + Text(target).font(.callout.monospaced()).foregroundColor(Theme.accent)
                    } icon: {
                        Image(systemName: note.meta["action"] == "append" ? "text.append" : "doc.badge.plus")
                    }
                    .font(.callout)
                    if let why = note.meta["why"] { Text(why).font(.caption).foregroundStyle(.secondary) }
                    if let o = note.meta["original"] {
                        Text("From \(o)").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }
            if let f = note.meta["privacy_flags"] {
                ErrorBanner(text: f, color: .orange, icon: "exclamationmark.shield.fill")
            }
            if isFiling {
                ScrollView {
                    Text(note.body.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.callout.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            } else {
                Text(preview).font(.callout).lineLimit(5).foregroundStyle(.primary.opacity(0.85))
            }
            HStack(spacing: 8) {
                Button { store.approveItem(note) } label: { Label(isFiling ? "File It" : "Approve", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent).tint(.green)
                Button(role: .destructive) { store.rejectItem(note) } label: { Label("Reject", systemImage: "xmark") }
                    .buttonStyle(.bordered)
                Spacer()
                if isFiling, let o = note.meta["original"] {
                    Button("Show Original") {
                        NSWorkspace.shared.activateFileViewerSelecting([Drop.filedDir.appendingPathComponent(o)])
                    }.buttonStyle(.link)
                }
                Button(isFiling ? "Edit" : "Open") {
                    if isFiling { store.editing = true }
                    store.opened = Opened(note: note, anchor: nil)
                }.buttonStyle(.link)
            }
            .controlSize(.regular)
        }
        .card()
    }
}

// MARK: - Link sheet

struct LinkSheet: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                KindTile(kind: "video", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a link").font(.title3.weight(.semibold))
                    Text("YouTube or another video or podcast page").font(.callout).foregroundStyle(.secondary)
                }
            }
            SearchFieldLike(text: $store.linkText)
            Text("Captions are used when available; otherwise the audio is transcribed on this Mac.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { store.showLinkSheet = false }.keyboardShortcut(.cancelAction)
                Button("Import") { store.importLink() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(!store.linkText.hasPrefix("http"))
            }
        }
        .padding(24)
        .frame(width: 480)
        .tint(Theme.accent)
    }
}

struct SearchFieldLike: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link").foregroundStyle(.secondary)
            TextField("https://…", text: $text).textFieldStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }
}

// MARK: - Markdown rendering (enough for answers and notes)

/// Inline Markdown; with `linkCitations`, "[n]" becomes a small raised accent
/// badge that links to mackb://cite/n.
func inlineMarkdown(_ s: String, linkCitations: Bool = false) -> AttributedString {
    var md = s
    if linkCitations {
        md = md.replacingOccurrences(of: #"\[(\d+)\]"#, with: "[\u{2009}$1\u{2009}](mackb://cite/$1)", options: .regularExpression)
    }
    guard var out = try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
        return AttributedString(s)
    }
    if linkCitations {
        let ranges = out.runs.filter { $0.link?.scheme == "mackb" }.map(\.range)
        for r in ranges {
            out[r].font = .system(size: 10, weight: .bold, design: .rounded)
            out[r].foregroundColor = Theme.accent
            out[r].backgroundColor = Theme.accent.opacity(0.13)
            out[r].baselineOffset = 3
        }
    }
    return out
}

struct MarkdownBlocks: View {
    var text: String
    var linkCitations = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Lines that are only citations ("[1]") add nothing once inline badges exist.
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true).filter {
                !linkCitations || $0.trimmingCharacters(in: .whitespaces).range(of: #"^(\[\d+\][\s,.]*)+$"#, options: .regularExpression) == nil
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, raw in
                let line = String(raw)
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    Text(inlineMarkdown(trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces), linkCitations: linkCitations))
                        .font(.system(size: 15, weight: .semibold)).padding(.top, 6)
                } else if let r = trimmed.range(of: #"^([*\-•]|\d+\.)\s+"#, options: .regularExpression) {
                    let marker = trimmed[r].trimmingCharacters(in: .whitespaces)
                    let indent = line.prefix(while: { $0 == " " }).count >= 2
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if marker.first?.isNumber == true {
                            Text(marker).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent).monospacedDigit()
                        } else {
                            Circle().fill(Theme.accent.opacity(0.7)).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                        }
                        Text(inlineMarkdown(String(trimmed[r.upperBound...]), linkCitations: linkCitations))
                            .font(.system(size: 14)).lineSpacing(3)
                    }
                    .padding(.leading, indent ? 20 : 2)
                } else {
                    Text(inlineMarkdown(trimmed, linkCitations: linkCitations))
                        .font(.system(size: 14)).lineSpacing(3)
                }
            }
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject var store: Store

    var filtered: [HistoryEntry] { store.history.filter { $0.matches(store.historySearch) } }

    /// Entries grouped under Today / Yesterday / the date, newest first.
    var groups: [(String, [HistoryEntry])] {
        let cal = Calendar.current
        var out: [(String, [HistoryEntry])] = []
        for e in filtered {
            let label = cal.isDateInToday(e.date) ? "Today"
                : cal.isDateInYesterday(e.date) ? "Yesterday"
                : e.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
            if out.last?.0 == label { out[out.count - 1].1.append(e) } else { out.append((label, [e])) }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(text: $store.historySearch, placeholder: "Search past questions and answers…")
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 10)
            if store.history.isEmpty {
                EmptyState(icon: "clock.arrow.circlepath", title: "No questions yet",
                           message: "Every question you ask is saved here with its answer and sources, in this vault.")
            } else if filtered.isEmpty {
                EmptyState(icon: "magnifyingglass", title: "No matches",
                           message: "Nothing in your past questions, answers or source titles matches \u{201C}\(store.historySearch)\u{201D}.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(groups, id: \.0) { label, entries in
                            SectionTitle(title: label, count: entries.count)
                            ForEach(entries) { e in HistoryRow(entry: e) }
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("History")
    }
}

struct HistoryRow: View {
    @EnvironmentObject var store: Store
    var entry: HistoryEntry
    @State private var hover = false

    var preview: String {
        entry.answer
            .replacingOccurrences(of: #"\[\d+\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*#_`]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        let selected = store.currentHistoryId == entry.id
        Button { store.openHistory(entry) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.question).font(.callout.weight(.semibold)).lineLimit(2)
                    Spacer(minLength: 8)
                    Text(entry.date, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(.tertiary)
                }
                Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 12) {
                    Label("\(entry.sources.count) sources", systemImage: "text.quote")
                    Label(entry.model, systemImage: "cpu")
                }
                .labelStyle(TightLabel())
                .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.1) : (hover ? Color.primary.opacity(0.04) : Theme.card)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Theme.accent.opacity(0.45) : Color.primary.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Copy Answer") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.answer, forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive) { store.deleteHistory(entry) }
        }
    }
}

/// Research mode's steps, shown above the answer.
struct StepsList: View {
    var steps: [String]
    var running: Bool
    @State private var open = true
    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: icon(s)).font(.caption).foregroundStyle(Theme.accent).frame(width: 14)
                        Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if running && i == steps.count - 1 { ProgressView().controlSize(.mini) }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text("\(steps.count) research step\(steps.count == 1 ? "" : "s")").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent.opacity(0.05)))
    }
    func icon(_ s: String) -> String {
        if s.hasPrefix("Searched") { return "magnifyingglass" }
        if s.hasPrefix("Read") { return "doc.text" }
        if s.hasPrefix("Listed tables") { return "tablecells" }
        if s.hasPrefix("Listed") { return "folder" }
        if s.hasPrefix("Queried") { return "function" }
        return "circle"
    }
}

/// The divider between the pane and the note: drag to resize (360–900 pt).
struct ResizeHandle: View {
    @Binding var width: Double
    @State private var start: Double?
    @State private var hover = false

    var body: some View {
        Rectangle()
            .fill(hover || start != nil ? Theme.accent.opacity(0.5) : Color(nsColor: .separatorColor))
            .frame(width: hover || start != nil ? 3 : 1)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .onHover { h in
                hover = h
                if h { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { g in
                    if start == nil { start = width }
                    width = min(900, max(360, (start ?? width) + g.translation.width))
                }
                .onEnded { _ in start = nil })
    }
}
