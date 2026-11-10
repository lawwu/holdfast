import AppKit
import SwiftUI

// MARK: - Design system

/// One accent (an obsidian-violet), cards on a soft canvas, and a colour per
/// kind of note. Light and dark mode both come from system colours.
enum Theme {
    static let accent = Color(red: 0.40, green: 0.33, blue: 0.88)
    static let accent2 = Color(red: 0.62, green: 0.36, blue: 0.93)
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let canvas = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.115, alpha: 1) : NSColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1)
    })
    static let card = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.16, alpha: 1) : .white
    })
    static let radius: CGFloat = 14
    /// Lists and pages sit in a column this wide when no note is open beside them.
    static let pageWidth: CGFloat = 860

    // Type scale: macOS's defaults (12pt callout, 10pt caption) read small for a reading app.
    static let body = Font.system(size: 15)
    static let callout = Font.system(size: 14)
    static let caption = Font.system(size: 12.5)
    static let caption2 = Font.system(size: 11.5)
    static let headline = Font.system(size: 15.5, weight: .semibold)
    static let title3 = Font.system(size: 19, weight: .semibold)
    static let title2 = Font.system(size: 22, weight: .semibold)

    /// Card surfaces: a soft fill with a hairline and a faint shadow.
    static let cardStroke = Color.primary.opacity(0.07)

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
            .shadow(color: .black.opacity(0.045), radius: 14, y: 4)
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
    /// A colour of its own (a note's folder colour), instead of the kind's.
    var tint: Color? = nil
    var body: some View {
        let c = tint ?? Theme.color(kind)
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(c.opacity(0.15))
            .frame(width: size, height: size)
            .overlay(Image(systemName: Theme.icon(kind)).font(.system(size: size * 0.46, weight: .medium)).foregroundStyle(c))
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
        .font(Theme.caption.weight(.medium))
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
        case .listen: ListenView()
        case .files: FilesView()
        case .tables: TablesView()
        case .graph: GraphView()
        }
    }

    /// The page with its title header (Ask and Graph draw their own top).
    @ViewBuilder var page: some View {
        let p = store.pane ?? .ask
        if p.fullBleed {
            paneView
        } else {
            VStack(spacing: 0) {
                PageHeader(pane: p)
                paneView
            }
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
                if store.opened == nil {
                    // Nothing open: lists sit in a readable column instead of stretching across the window.
                    page
                        .frame(maxWidth: (store.pane ?? .ask).wide ? .infinity : Theme.pageWidth)
                        .frame(maxWidth: .infinity)
                        .background(Theme.canvas)
                } else {
                    if store.showList {
                        page
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
        .sheet(isPresented: $store.showBulkImport) { BulkImportSheet().environmentObject(store) }
        .sheet(isPresented: $store.showRemoteSetup) { RemoteSetupSheet().environmentObject(store) }
        .sheet(isPresented: $store.showExport) { ExportSheet().environmentObject(store) }
        .sheet(item: $store.reading) { t in ConversationReader(thread: t.id).environmentObject(store) }
        .overlay {
            // Quick Open and the command palette float like Spotlight: a click outside closes them.
            if store.showQuickOpen || store.showPalette {
                FloatingPanel(close: { store.showQuickOpen = false; store.showPalette = false }) {
                    if store.showQuickOpen { QuickOpen() } else { CommandPalette() }
                }
            }
        }
        .sheet(item: $store.preview) { o in
            NotePreview(opened: o).environmentObject(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Notes may have changed outside the app (Obsidian, Claude Code, git pull).
            if !store.editing { store.reload() }
        }
        .environment(\.openURL, OpenURLAction { url in store.handleLink(url) ? .handled : .systemAction })
        // Selectable text (answers, notes) sends link clicks to macOS rather than to openURL above;
        // the app registers its link schemes (make_app.sh), so macOS hands them back here.
        .onAppear { AppDelegate.openLink = { [weak store] url in store?.handleLink(url) ?? false } }
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
            Text(title).font(Theme.title3.weight(.semibold))
            Text(message).font(Theme.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var listener = Listener.shared

    var body: some View {
        List(selection: $store.pane) {
            ForEach(Array(Pane.groups.enumerated()), id: \.offset) { i, g in
                Section {
                    ForEach(g.panes) { p in row(p) }
                } header: {
                    if i == 0 { brand } else if let t = g.title { Text(t) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { VaultCard().padding(10) }
    }

    var brand: some View {
        HStack(spacing: 10) {
            AppMark(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Holdfast").font(.system(size: 15.5, weight: .semibold)).foregroundStyle(.primary)
                Text("Your notes never leave home").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .padding(.bottom, 12)
        .padding(.top, 4)
    }

    @ViewBuilder func row(_ p: Pane) -> some View {
        HStack(spacing: 0) {
            Label(p.rawValue, systemImage: p.icon)
                .font(.system(size: 14, weight: .medium))
            Spacer(minLength: 4)
            if p == .listen, listener.active {
                Circle().fill(Color.red).frame(width: 7, height: 7).help("Listening now")
            }
            if p == .ask, store.busy != nil, !store.askedQuestion.isEmpty, store.pane != .ask {
                ProgressView().controlSize(.mini).help("Writing an answer")
            }
        }
        .padding(.vertical, 3)
        .badge(p == .inbox ? store.inboxItems.count : 0)
        .tag(p)
    }
}

/// The title at the top of a page: what it is, in one line.
struct PageHeader: View {
    var pane: Pane
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.accent.opacity(0.12))
                .frame(width: 38, height: 38)
                .overlay(Image(systemName: pane.icon).font(.system(size: 17, weight: .medium)).foregroundStyle(Theme.accent))
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.rawValue).font(.system(size: 24, weight: .semibold, design: .rounded))
                if !pane.subtitle.isEmpty {
                    Text(pane.subtitle).font(Theme.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct VaultCard: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var listener = Listener.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if listener.active, store.pane != .listen {
                Button { store.pane = .listen } label: { ListeningBadge() }.buttonStyle(.plain)
                Divider()
            }
            if let b = store.busy, store.pane != .ask {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(b).font(Theme.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Divider()
            }
            Button { store.chooseVault() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                    Text(store.vault.lastPathComponent).font(Theme.callout.weight(.medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down").font(Theme.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(store.vault.path) — click to choose another vault")
            HStack(spacing: 12) {
                Label("\(store.notes.count)", systemImage: "doc.on.doc").help("Notes")
                Label("\(store.indexCounts.chunks)", systemImage: "text.alignleft").help("Indexed passages")
            }
            .font(Theme.caption).foregroundStyle(.secondary).labelStyle(TightLabel())
            HStack(spacing: 5) {
                Image(systemName: store.backend == .remote ? "network" : "lock.fill")
                Text(store.backend == .remote ? "Notes here · model on \(Remote.host)" : "Stays on this Mac")
            }
            .font(Theme.caption2.weight(.medium)).foregroundStyle(store.backend == .remote ? Color.orange : .green)
            .help(store.backend == .remote ? "Your vault and search stay on this Mac. Questions, the passages found, the conversation and documents to file go to \(Remote.host); counseling notes never do." : "Notes, search and the model all run on this Mac.")
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
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(store.turns) { t in
                                TurnView(entry: t)
                                Divider()
                            }
                            QuestionHeader(text: store.askedQuestion)
                            if let b = store.busy { StatusPill(text: b, since: store.turnStarted) }
                            if let e = store.error { ErrorBanner(text: e) }
                            if !store.answer.isEmpty || !store.steps.isEmpty { AnswerCard() }
                            if !store.sources.isEmpty { SourcesSection() }
                            Color.clear.frame(height: 1).id("turn-end")
                        }
                        .padding(.horizontal, 28).padding(.vertical, 26)
                        .frame(maxWidth: 820, alignment: .leading)
                        .frame(maxWidth: .infinity)
                    }
                    // A new question starts at the bottom of the conversation, where it is asked.
                    .onChange(of: store.askedQuestion) { proxy.scrollTo("turn-end", anchor: .bottom) }
                }
                AskNotices().frame(maxWidth: 772).padding(.horizontal, 24)
                Composer()
                    .padding(.horizontal, 24).padding(.bottom, 18).padding(.top, 8)
                    .frame(maxWidth: 820)
            } else {
                AskHero()
            }
        }
        .navigationTitle("Ask")
        .toolbar {
            if hasConversation {
                ToolbarItem {
                    Button { store.newQuestion() } label: { Label("New Conversation", systemImage: "square.and.pencil") }
                        .disabled(store.busy != nil)
                        .help("Start a new conversation (⌘N). This one is saved in History; open it there to pick it up again.")
                        .keyboardShortcut("n")
                }
            }
        }
    }
}

/// Cards that sit above the question box: a job waiting for a go-ahead, and first-run guidance.
struct AskNotices: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(spacing: 10) {
            if store.pendingJob == .crossLink {
                JobConfirmCard(title: "Suggest links between notes?",
                               detail: "Holdfast finds pairs of closely related notes that don't link yet and asks the model about each pair (a few minutes). Suggestions wait in the Inbox for your approval; counseling notes are left out.",
                               start: { store.pendingJob = nil; store.runCrossLink() },
                               cancel: { store.pendingJob = nil })
            }
            if store.backend == .mlx, !store.isDownloaded(store.mlxRepo) {
                FirstRunCard()
            }
        }
    }
}

/// The Ask page before a question: the question box in the middle, then what needs attention
/// (proposals to approve, follow-ups coming due) and where you left off.
struct AskHero: View {
    @EnvironmentObject var store: Store
    var suggestions: [(String, String)] { store.profile.suggestions.map { ($0.icon, $0.text) } }
    var waiting: Int { store.inboxItems.count }

    var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 30)
                VStack(spacing: 8) {
                    AppMark(size: 46)
                    Text(greeting).font(.system(size: 30, weight: .semibold, design: .rounded)).padding(.top, 6)
                    HStack(spacing: 6) {
                        Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                        Text("·")
                        Text("\(store.notes.count) notes in \(store.vault.lastPathComponent)")
                    }
                    .font(Theme.callout).foregroundStyle(.secondary)
                }
                AskNotices()
                Composer()
                if !store.pins.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PINNED").font(Theme.caption.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(store.pins) { p in
                                SuggestionCard(icon: "pin.fill", text: p.question) { store.askSuggested(p.question) }
                                    .contextMenu { Button("Unpin") { store.togglePin(p.question) } }
                            }
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(suggestions, id: \.1) { icon, q in SuggestionCard(icon: icon, text: q) { store.askSuggested(q) } }
                }
                if waiting > 0 {
                    Button { store.pane = .inbox } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "tray.full.fill").foregroundStyle(Theme.accent)
                            Text("\(waiting) proposal\(waiting == 1 ? "" : "s") waiting for your approval").font(Theme.callout.weight(.medium))
                            Spacer()
                            Text("Review").font(Theme.callout.weight(.semibold)).foregroundStyle(Theme.accent)
                            Image(systemName: "chevron.right").font(Theme.caption).foregroundStyle(Theme.accent)
                        }
                        .card(padding: 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ImportProgressBar()
                HStack(alignment: .top, spacing: 14) {
                    UpcomingCard()
                    RecentCard()
                }
                AddFilesCard()
                Spacer(minLength: 20)
            }
            .frame(maxWidth: 700)
            .padding(.horizontal, 24).padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }
}

/// The last few conversations, to pick up where you left off.
struct RecentCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if !store.history.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("RECENT").font(Theme.caption.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
                    Spacer()
                    Button("See all") { store.pane = .history }.buttonStyle(.link).font(Theme.caption)
                }
                ForEach(store.conversations.prefix(5), id: \.latest.id) { c in
                    Button { store.openHistory(c.latest) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: c.count > 1 ? "bubble.left.and.bubble.right" : "bubble.left").foregroundStyle(.secondary).font(Theme.caption)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.first.question).font(Theme.callout).lineLimit(1).foregroundStyle(.primary)
                                Text(c.latest.date, format: .relative(presentation: .named)).font(Theme.caption).foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
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
                Text(store.dropStatus ?? "Add files to your knowledge base").font(Theme.callout.weight(.semibold))
                Text(Config.inPlace ? "Drop documents, photos or recordings here; the model proposes where each belongs."
                                    : "Drop documents or recordings here to import them.")
                    .font(Theme.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if waiting > 0 {
                Button("\(waiting) to review") { store.pane = .inbox }.buttonStyle(.link).font(Theme.caption)
            }
            Button("Bulk Import…") { store.showBulkImport = true }.buttonStyle(.bordered).controlSize(.regular)
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
                Text(text).font(Theme.callout).multilineTextAlignment(.leading).foregroundStyle(.primary)
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
        Text(text)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .textSelection(.enabled)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.gradient))
            .frame(maxWidth: 600, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct StatusPill: View {
    var text: String
    var since: Date? = nil
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(Theme.callout).foregroundStyle(.secondary)
            if let since {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text("\(Int(ctx.date.timeIntervalSince(since)))s").font(Theme.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
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
            Text(text).font(Theme.callout).textSelection(.enabled)
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
            if !store.steps.isEmpty { StepsList(steps: store.steps, running: store.busy != nil) }
            MarkdownBlocks(text: store.answer, linkCitations: true)
            if let w = store.warning {
                ErrorBanner(text: w, color: .orange, icon: "exclamationmark.triangle.fill")
            }
            if let s = store.answerStats {
                Divider()
                if let r = store.routeNote {
                    Label(r, systemImage: "arrow.triangle.branch").font(Theme.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    Label("\(s.passages) passages", systemImage: "text.quote")
                    Label("\(s.tokens) tokens", systemImage: "number")
                    Label(String(format: "%.1f tok/s", s.tokPerSec), systemImage: "gauge.with.dots.needle.67percent")
                    Label(String(format: "%.0f s", s.seconds), systemImage: "clock")
                    Spacer()
                    Label(store.history.first { $0.id == store.currentHistoryId }?.model ?? store.modelLabel, systemImage: "cpu")
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.answer, forType: .string)
                    } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy the answer")
                    Button { store.togglePin(store.askedQuestion) } label: {
                        Label(store.isPinned(store.askedQuestion) ? "Pinned" : "Pin", systemImage: store.isPinned(store.askedQuestion) ? "pin.fill" : "pin")
                    }
                    .buttonStyle(.borderless).help("Keep this question on the Ask home page, to ask again with one click")
                }
                .labelStyle(TightLabel())
                .font(Theme.caption).foregroundStyle(.secondary)
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
                Text("Sources").font(Theme.headline)
                Text("\(store.sources.count)").font(Theme.caption.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(.quaternary))
            }
            // Most relevant first; each card keeps the number the answer cites it by.
            let ranked = store.sources.enumerated().sorted { ($0.element.score ?? 0) > ($1.element.score ?? 0) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 10, alignment: .top)], spacing: 10) {
                ForEach(ranked, id: \.offset) { i, c in
                    SourceCard(n: i + 1, chunk: c)
                }
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
                        .font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.accent)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.accent.opacity(0.12)))
                } else {
                    KindTile(kind: kind, size: 26)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(chunk.title).font(Theme.callout.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        if let s = chunk.score { RelevanceMeter(score: s) }
                    }
                    if chunk.anchor != chunk.title {
                        Text(chunk.anchor).font(Theme.caption.weight(.medium)).foregroundStyle(Theme.accent).lineLimit(1)
                    }
                    if !snippet.isEmpty {
                        Text(snippet).font(Theme.caption).foregroundStyle(.secondary).lineLimit(2)
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
            Text(String(format: "%.0f%%", score * 100)).font(Theme.caption2).monospacedDigit().foregroundStyle(.secondary)
        }
        .help("How relevant the reranker judged this passage to your question (0–100%). Not a probability of being right: passages that score low next to the best one are left out, so a lower one still made the cut.")
    }
}

struct Composer: View {
    @EnvironmentObject var store: Store
    @FocusState private var focused: Bool

    var canSend: Bool { store.busy == nil && !store.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(store.conversationId != nil && !store.askedQuestion.isEmpty ? "Ask a follow-up…"
                          : store.profile == .counseling ? "Ask about your materials and case reports…" : "Ask, or tell Holdfast what to do…",
                          text: $store.question, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .lineLimit(1...8)
                    .focused($focused)
                    .onSubmit { store.runAsk() }
                    .padding(.vertical, 5)
                if store.busy != nil && !store.askedQuestion.isEmpty {
                    // While an answer is being written: Stop (keeps what's written so far).
                    Button { store.stopAsk() } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Theme.gradient))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(".", modifiers: .command)
                    .help("Stop generating (⌘.)")
                    .accessibilityLabel("Stop generating")
                } else {
                Button { store.runAsk() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(canSend ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.secondary.opacity(0.35))))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend)
                .help("Ask (Return)")
                .accessibilityLabel("Ask")
                }
            }
            .padding(.leading, 18).padding(.trailing, 10).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
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
                    Section("Another Mac") {
                        if let u = Remote.url, !Remote.model.isEmpty {
                            Toggle("\(Remote.model) · \(u.host ?? "")", isOn: Binding(
                                get: { store.backend == .remote },
                                set: { if $0 { store.backend = .remote } }))
                        }
                        Button("Set Up…") { store.showRemoteSetup = true }
                    }
                    if store.backend == .ollama {
                        Section("Ollama") {
                            Toggle("\(Config.llmModel) · Ollama", isOn: Binding(
                                get: { store.backend == .ollama },
                                set: { if $0 { store.backend = .ollama } }))
                        }
                    }
                    Divider()
                    Toggle("Show Thinking (slower)", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "showThinking") },
                        set: { UserDefaults.standard.set($0, forKey: "showThinking") }))
                    SettingsLink { Text("More Models…") }
                } label: {
                    Label(store.modelLabel, systemImage: "cpu")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .font(Theme.caption)
                Button { store.chooseFilesToAdd() } label: {
                    Label("Add Files", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(Config.inPlace
                      ? "Add documents, photos or recordings. The model proposes where each belongs; you approve it in the Inbox."
                      : "Add documents or recordings to the vault as sources.")
                Spacer()
                Label(store.backend == .remote ? "Sent to \(Remote.host) · counseling stays here" : "Private · nothing leaves this Mac",
                      systemImage: store.backend == .remote ? "network" : "lock.fill")
                    .labelStyle(TightLabel())
                    .font(Theme.caption).foregroundStyle(store.backend == .remote ? Color.orange : .secondary)
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
                PacksSection().padding(.horizontal, 20)
                EmptyState(icon: "books.vertical", title: "Your library is empty",
                           message: "Import documents, recordings or a folder with ⌘I, or add a link with ⌘L.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8, pinnedViews: []) {
                        if searching {
                            SectionTitle(title: "Results", count: store.results.count)
                            ForEach(Array(store.results.enumerated()), id: \.offset) { _, c in SourceCard(chunk: c) }
                        } else {
                            PacksSection().padding(.bottom, 8)
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
            Text(title.uppercased()).font(Theme.caption.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
            Text("\(count)").font(Theme.caption).foregroundStyle(.tertiary)
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
            .font(Theme.caption.weight(.medium))
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

    /// The note's folder in a vault indexed in place ("finance/taxes"); nil at the top level or in a managed vault.
    var folder: String? {
        guard Config.inPlace, !note.relPath.hasPrefix("@"), !Packs.isPack(note.relPath) else { return nil }
        let dir = (note.relPath as NSString).deletingLastPathComponent
        return dir.isEmpty ? nil : dir
    }
    /// Plain documents take their top folder's colour, so the Library reads by area at a glance.
    var tint: Color? {
        guard Theme.kind(of: note) == "document", let top = folder?.split(separator: "/").first else { return nil }
        return domainColor(String(top))
    }

    var subtitle: String {
        var parts: [String] = []
        if let f = folder { parts.append(f) }
        if let c = note.meta["case"] { parts.append(c) }
        if let s = note.meta["session"] { parts.append("Session \(s)") }
        if let k = note.meta["session_kind"] { parts.append(k) }
        if let d = note.meta["date"] ?? note.meta["created"] { parts.append(String(d.prefix(10))) }
        if let t = note.meta["tags"], !t.isEmpty, t != note.meta["doc_type"] { parts.append(t) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let selected = store.opened?.note.path == note.path
        Button { store.openNote(note, doubleClicked: NSApp.currentEvent?.clickCount == 2) } label: {
            HStack(spacing: 12) {
                KindTile(kind: Theme.kind(of: note), size: 32, tint: tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title).font(Theme.callout.weight(.medium)).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(Theme.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(Theme.caption.weight(.semibold)).foregroundStyle(.tertiary)
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
                ImportProgressBar()
                NoticeBanner()
                ForEach(store.ruleSuggestions) { c in RuleSuggestionCard(c: c) }
                if store.inboxItems.isEmpty {
                    EmptyState(icon: "tray", title: "All caught up",
                               message: Config.inPlace
                               ? "Files you drop are read by the model, which proposes where each belongs. Proposals, and memories agents ask to save, wait here for your approval."
                               : "Memories that agents (like Claude Code over MCP) propose to save wait here for your approval.")
                        .frame(minHeight: 260)
                } else {
                    Text("Nothing is written until you approve.")
                        .font(Theme.callout).foregroundStyle(.secondary)
                    let groups = Dictionary(grouping: store.inboxItems.filter { filingPlace($0) != nil }, by: { filingPlace($0)! })
                    let grouped = groups.filter { $0.value.count > 1 }
                    ForEach(grouped.keys.sorted(), id: \.self) { place in
                        FilingGroupHeader(place: place, items: grouped[place]!)
                        ForEach(grouped[place]!, id: \.path) { n in InboxCard(note: n) }
                    }
                    ForEach(store.inboxItems.filter { filingPlace($0).map { grouped[$0] == nil } ?? true }, id: \.path) { n in InboxCard(note: n) }
                }
                RecentFilings()
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
                    Text(store.dropStatus ?? "Drop files to add them to the vault").font(Theme.headline)
                    Text(Config.inPlace
                         ? "PDFs, Word, Markdown, images (read on-device), recordings. The model proposes a note or a log entry; you approve it below."
                         : "Documents and recordings are imported as sources and indexed.")
                        .font(Theme.caption).foregroundStyle(.secondary)
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
    var isEdit: Bool { isFiling && note.meta["action"] == "edit" }

    var preview: String {
        note.body.split(separator: "\n").filter { !$0.hasPrefix("#") }.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                KindTile(kind: isFiling ? "document" : "memory", size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.title).font(Theme.headline)
                    Text("Proposed by \(note.meta["proposed_by"] ?? "an agent")\(note.meta["proposed"].map { " · \($0)" } ?? "")")
                        .font(Theme.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if isFiling, let target = note.meta["target"] {
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text(isEdit ? "Change " : note.meta["action"] == "link" ? "Add a link in " : note.meta["action"] == "append" ? "Append to " : "New note ")
                            + Text(target).font(Theme.callout.monospaced()).foregroundColor(Theme.accent)
                    } icon: {
                        Image(systemName: isEdit ? "pencil" : note.meta["action"] == "link" ? "link" : note.meta["action"] == "append" ? "text.append" : "doc.badge.plus")
                    }
                    .font(Theme.callout)
                    if let why = note.meta["why"] { Text(why).font(Theme.caption).foregroundStyle(.secondary) }
                    if let o = note.meta["original"] {
                        Text("From \(o)" + (note.meta["from"].map { " · sent by \($0)" } ?? "")).font(Theme.caption).foregroundStyle(.tertiary)
                    }
                    if let r = note.meta["rule"] {
                        Label("Filing rule: \(r)", systemImage: "wand.and.stars").font(Theme.caption).foregroundStyle(Theme.accent)
                    }
                    let props = Drop.properties(note)
                    if !props.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(props.sorted { $0.key < $1.key }, id: \.key) { k, v in
                                Text("\(k): \(v)").font(Theme.caption.monospaced()).lineLimit(1)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                            }
                        }
                    }
                    ForEach(Array(Drop.followUps(note).enumerated()), id: \.offset) { _, f in
                        Label((f.date.isEmpty ? "" : f.date + " · ") + f.what, systemImage: "circle").font(Theme.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if let f = note.meta["privacy_flags"] {
                ErrorBanner(text: f, color: .orange, icon: "exclamationmark.shield.fill")
            }
            if isEdit, let target = note.meta["target"] {
                EditDiff(target: target, proposed: note.body)
            } else if isFiling {
                ScrollView {
                    Text(note.body.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(Theme.callout.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
            } else {
                Text(preview).font(Theme.callout).lineLimit(5).foregroundStyle(.primary.opacity(0.85))
            }
            HStack(spacing: 8) {
                Button { store.approveItem(note) } label: { Label(isEdit ? "Apply Change" : isFiling ? "File It" : "Approve", systemImage: "checkmark") }
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

/// What a proposed change does to a note: removed lines in red, added in green, a little context.
struct EditDiff: View {
    var target: String
    var proposed: String
    var body: some View {
        let current = (try? Drop.safeTarget(target)).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        VStack(alignment: .leading, spacing: 6) {
            if let current {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(Edits.diff(current, proposed).enumerated()), id: \.offset) { _, l in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(l.kind == "…" ? "⋯" : String(l.kind)).foregroundStyle(.secondary).frame(width: 10)
                                Text(l.text.isEmpty ? " " : l.text).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(Theme.callout.monospaced())
                            .foregroundStyle(l.kind == " " || l.kind == "…" ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(l.kind == "+" ? Color.green.opacity(0.14) : l.kind == "-" ? Color.red.opacity(0.13) : .clear)
                        }
                    }
                    .textSelection(.enabled)
                }
                .frame(maxHeight: 260)
            } else {
                ErrorBanner(text: "\(target) isn't there any more; reject this change.", color: .orange, icon: "exclamationmark.triangle.fill")
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
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
                    Text("Add a link").font(Theme.title3.weight(.semibold))
                    Text("YouTube or another video or podcast page").font(Theme.callout).foregroundStyle(.secondary)
                }
            }
            SearchFieldLike(text: $store.linkText)
            Text("Captions are used when available; otherwise the audio is transcribed on this Mac.")
                .font(Theme.caption).foregroundStyle(.secondary)
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
/// badge that links to holdfast://cite/n.
func inlineMarkdown(_ s: String, linkCitations: Bool = false) -> AttributedString {
    var md = s
    if linkCitations {
        md = md.replacingOccurrences(of: #"\[(\d+)\]"#, with: "[\u{2009}$1\u{2009}](holdfast://cite/$1)", options: .regularExpression)
    }
    guard var out = try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
        return AttributedString(s)
    }
    if linkCitations {
        let ranges = out.runs.filter { $0.link?.scheme == "holdfast" }.map(\.range)
        for r in ranges {
            out[r].font = .system(size: 11, weight: .bold, design: .rounded)
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
                        .font(.system(size: 16.5, weight: .semibold)).padding(.top, 6)
                } else if let r = trimmed.range(of: #"^([*\-•]|\d+\.)\s+"#, options: .regularExpression) {
                    let marker = trimmed[r].trimmingCharacters(in: .whitespaces)
                    let indent = line.prefix(while: { $0 == " " }).count >= 2
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if marker.first?.isNumber == true {
                            Text(marker).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(Theme.accent).monospacedDigit()
                        } else {
                            Circle().fill(Theme.accent.opacity(0.7)).frame(width: 5, height: 5).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                        }
                        Text(inlineMarkdown(String(trimmed[r.upperBound...]), linkCitations: linkCitations))
                            .font(.system(size: 15.5)).lineSpacing(3)
                    }
                    .padding(.leading, indent ? 20 : 2)
                } else {
                    Text(inlineMarkdown(trimmed, linkCitations: linkCitations))
                        .font(.system(size: 15.5)).lineSpacing(3)
                }
            }
        }
        .textSelection(.enabled)
    }
}

// MARK: - History

struct HistoryView: View {
    @EnvironmentObject var store: Store

    /// The latest turn of each conversation with any turn matching the search.
    var filtered: [HistoryEntry] {
        store.conversations.filter { c in store.history.contains { $0.thread == c.latest.thread && $0.matches(store.historySearch) } }.map(\.latest)
    }

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
        let selected = store.conversationId == entry.thread
        let convo = store.conversations.first { $0.latest.id == entry.id }
        Button { store.openHistory(entry) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(convo?.first.question ?? entry.question).font(Theme.callout.weight(.semibold)).lineLimit(2)
                    if let n = convo?.count, n > 1 {
                        Text("\(n) turns").font(Theme.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(.quaternary))
                    }
                    Spacer(minLength: 8)
                    Text(entry.date, format: .dateTime.hour().minute()).font(Theme.caption).foregroundStyle(.tertiary)
                }
                Text(preview).font(Theme.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 12) {
                    Label("\(entry.sources.count) sources", systemImage: "text.quote")
                    Label(entry.model, systemImage: "cpu")
                }
                .labelStyle(TightLabel())
                .font(Theme.caption2).foregroundStyle(.tertiary)
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

/// What Holdfast did, step by step. A step with a detail (the exact tool call and
/// what it returned, or the model's reasoning) opens when clicked.
struct StepsList: View {
    var steps: [String]
    var running: Bool
    @State private var open = true
    @State private var expanded: Set<Int> = []
    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, raw in
                    let (title, detail) = Steps.split(raw)
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            if detail != nil { if expanded.contains(i) { expanded.remove(i) } else { expanded.insert(i) } }
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: icon(title)).font(Theme.caption).foregroundStyle(Theme.accent).frame(width: 14)
                                Text(title).font(Theme.caption).foregroundStyle(.secondary).lineLimit(2)
                                if detail != nil {
                                    Image(systemName: expanded.contains(i) ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                                }
                                if running && i == steps.count - 1 { ProgressView().controlSize(.mini) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(detail == nil)
                        .help(detail == nil ? "" : "Show the exact call and what came back")
                        if let detail, expanded.contains(i) {
                            ScrollView {
                                Text(detail).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 200)
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                            .padding(.leading, 22)
                        }
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Text(running ? "Working…" : "\(steps.count) step\(steps.count == 1 ? "" : "s")").font(Theme.caption.weight(.semibold)).foregroundStyle(.secondary)
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
        if s.hasPrefix("Searching") { return "magnifyingglass" }
        if s.hasPrefix("Planning") { return "list.bullet.indent" }
        if s.hasPrefix("No direct") || s.hasPrefix("Found nothing") { return "arrow.down.right.circle" }
        if s.hasPrefix("Done") { return "checkmark.circle" }
        if s.hasPrefix("Stopped") { return "stop.circle" }
        if s.hasPrefix("Thinking") { return "brain" }
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
