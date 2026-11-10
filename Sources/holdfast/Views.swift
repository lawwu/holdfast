import AppKit
import SwiftUI

// MARK: - Design system

/// Paper & Pine: quiet navigation, warm paper, and a single evergreen accent.
enum Theme {
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
    static let accent = adaptive(0x35624E, 0xA4C6A9)
    static let accent2 = accent
    static let gradient = LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let canvas = adaptive(0xF5F4EF, 0x1C211F)
    static let paper = adaptive(0xFDFCF9, 0x222624)
    static let sidebar = adaptive(0xEAECE5, 0x181E1B)
    static let ink = adaptive(0x25362D, 0xE4E7DE)
    static let secondary = adaptive(0x687166, 0xA7B1A7)
    static let selection = adaptive(0xDCE6D9, 0x344637)
    static let button = adaptive(0x315843, 0xB1CEB2)
    static let onButton = adaptive(0xFFFEF8, 0x1A2C20)
    static let card = paper
    static let radius: CGFloat = 10
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
    static let editorial = Font.system(size: 32, weight: .regular, design: .serif)

    static let cardStroke = adaptive(0xDEDFD6, 0x343D36)

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
                    .strokeBorder(highlighted ? Theme.accent.opacity(0.6) : Theme.cardStroke, lineWidth: highlighted ? 1.5 : 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16, highlighted: Bool = false) -> some View {
        modifier(CardStyle(padding: padding, highlighted: highlighted))
    }
}

/// A quiet, monochrome glyph; note kind is communicated by its shape.
struct KindTile: View {
    var kind: String
    var size: CGFloat = 30
    var body: some View {
        Image(systemName: Theme.icon(kind))
            .font(.system(size: size * 0.48, weight: .regular))
            .foregroundStyle(Theme.secondary)
            .frame(width: size, height: size)
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
        Image(nsImage: HoldfastIcon.mark)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Dock icon, drawn at launch (the bundle has no asset catalog).
@MainActor func renderAppIcon() -> NSImage? {
    HoldfastIcon.image()
}

// MARK: - Root

struct RootView: View {
    @EnvironmentObject var store: Store
    /// Width of the pane beside a note; drag the divider to change it.
    @AppStorage("paperPineBrowserWidth") private var browserWidth: Double = 300
    @AppStorage("paperPineDetailWidth") private var detailWidth: Double = 520

    private var pane: Pane { store.pane ?? .ask }
    private var width: Binding<Double> { pane.compactBrowser ? $browserWidth : $detailWidth }
    private var minimumWidth: Double { pane.compactBrowser ? 260 : 420 }

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
        if p.isLibrary {
            VStack(spacing: 0) {
                LibraryNavigation()
                paneView
            }
        } else if p.fullBleed {
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
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
        } detail: {
          GeometryReader { geometry in
            HStack(spacing: 0) {
                if store.opened == nil {
                    // Nothing open: lists sit in a readable column instead of stretching across the window.
                    page
                        .frame(maxWidth: (store.pane ?? .ask).wide ? .infinity : Theme.pageWidth)
                        .frame(maxWidth: .infinity)
                        .background(pane == .ask ? Theme.paper : Theme.canvas)
                } else {
                    if store.showList {
                        page
                            .background(pane == .ask ? Theme.paper : Theme.canvas)
                            .frame(width: min(max(minimumWidth, width.wrappedValue), max(minimumWidth, geometry.size.width - 468)))
                        ResizeHandle(width: width, minimum: minimumWidth,
                                     maximum: max(minimumWidth, geometry.size.width - 468))
                    }
                    if let o = store.opened {
                        VStack(spacing: 0) {
                            TabBar()
                            NoteView(opened: o)
                        }
                        .frame(minWidth: 420, maxWidth: .infinity)
                        .background(Theme.paper)
                    } else {
                        EmptyState(icon: "doc.text.magnifyingglass", title: "Nothing open",
                                   message: "Click a citation, a source or a note to read it here.")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .background(Theme.canvas)
            .animation(.easeOut(duration: 0.18), value: store.showList)
          }
        }
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .onChange(of: store.pane) { _, _ in store.showList = true }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Files or Folder…", systemImage: "square.and.arrow.down") { store.importFiles() }
                    Button("Link…", systemImage: "link") { store.showLinkSheet = true }
                    Button("New Note", systemImage: "square.and.pencil") { store.createNote(near: store.opened?.note) }
                    Divider()
                    Button("Bulk Import…") { store.showBulkImport = true }
                } label: { Label("Add", systemImage: "plus").labelStyle(.titleAndIcon) }
                .help("Add documents, recordings, links or a new note")
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
            Text("\(store.notes.count) notes").font(Theme.caption).foregroundStyle(Theme.secondary)
                .help("\(store.indexCounts.chunks) indexed passages")
            HStack(spacing: 5) {
                Image(systemName: store.backend != .mlx ? "network" : "lock.fill")
                Text(store.backend.locationLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Theme.caption2.weight(.medium)).foregroundStyle(store.backend != .mlx ? Color.orange : Theme.accent)
            .help(store.backend.privacyHelp)
        }
        .padding(.horizontal, 6).padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.cardStroke).frame(height: 1) }
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
                               detail: "Holdfast finds pairs of closely related notes that don't link yet and asks the model about each pair (a few minutes). Suggestions wait in the Inbox for your approval; private notes are left out.",
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
                VStack(alignment: .leading, spacing: 10) {
                    Text("ASK YOUR NOTES").font(Theme.caption2.weight(.medium)).tracking(1.4).foregroundStyle(Theme.accent)
                    Text(greeting).font(.system(size: 38, weight: .regular, design: .serif))
                    HStack(spacing: 6) {
                        Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                        Text("·")
                        Text("\(store.notes.count) notes in \(store.vault.lastPathComponent)")
                    }
                    .font(Theme.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
            .padding(12)
            .background(hover ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardStroke).frame(height: 1) }
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
            .font(.system(size: 28, weight: .regular, design: .serif))
            .foregroundStyle(Theme.ink)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 18) {
            if !store.steps.isEmpty { StepsList(steps: store.steps, running: store.busy != nil) }
            MarkdownBlocks(text: store.answer, linkCitations: true)
            if let w = store.warning {
                ErrorBanner(text: w, color: .orange, icon: "exclamationmark.triangle.fill")
            }
            if let stats = store.answerStats {
                HStack(spacing: 16) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.answer, forType: .string)
                    } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .help("Copy the answer")
                    Button { store.togglePin(store.askedQuestion) } label: {
                        Label(store.isPinned(store.askedQuestion) ? "Pinned" : "Pin", systemImage: store.isPinned(store.askedQuestion) ? "pin.fill" : "pin")
                    }
                    .help("Keep this question on the Ask home page")
                    Spacer(minLength: 0)
                }
                .buttonStyle(.borderless).font(Theme.caption).foregroundStyle(Theme.secondary)
                AnswerDetails(stats: stats,
                              model: store.history.first { $0.id == store.currentHistoryId }?.model ?? store.modelLabel,
                              route: store.routeNote)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AnswerDetails: View {
    var stats: AnswerStats
    var model: String
    var route: String?
    var body: some View {
        DisclosureGroup("Answer details") {
            VStack(alignment: .leading, spacing: 8) {
                if let route { Text(route) }
                Text(model)
                Text("\(stats.passages) passages · \(stats.tokens) tokens · "
                     + String(format: "%.1f tok/s · %.0f s", stats.tokPerSec, stats.seconds))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
            .textSelection(.enabled)
        }
        .font(Theme.caption).foregroundStyle(Theme.secondary)
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
            LazyVStack(alignment: .leading, spacing: 4) {
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
    @State private var expanded = false

    var isOpen: Bool { store.opened?.note.relPath == chunk.relPath && store.opened?.anchor == chunk.anchor }
    var snippet: String {
        chunk.text.split(separator: "\n").dropFirst().joined(separator: " ")
            .replacingOccurrences(of: #"#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Button { store.open(chunk) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        if let n {
                            Text("\(n)").font(Theme.caption.weight(.medium)).monospacedDigit()
                                .foregroundStyle(Theme.accent).frame(width: 22, height: 22)
                                .background(Theme.selection, in: RoundedRectangle(cornerRadius: 5))
                        } else {
                            Image(systemName: "doc.text").foregroundStyle(Theme.secondary)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(chunk.title).font(Theme.callout.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(2)
                            if chunk.anchor != chunk.title {
                                Text(chunk.anchor).font(Theme.caption).foregroundStyle(Theme.accent).lineLimit(1)
                            }
                            if !snippet.isEmpty, !expanded {
                                Text(snippet).font(Theme.caption).foregroundStyle(Theme.secondary).lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Open this passage in its note")
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(Theme.caption).frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(expanded ? "Hide passage preview" : "Preview passage")
                .accessibilityLabel(expanded ? "Hide passage preview" : "Preview passage")
            }
            if expanded {
                MarkdownBlocks(text: chunk.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.accent).frame(width: 2) }
                if let score = chunk.score {
                    DisclosureGroup("Retrieval details") { RelevanceMeter(score: score).padding(.top, 6) }
                        .font(Theme.caption).foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(12)
        .background(hover || isOpen ? Theme.selection.opacity(0.45) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.cardStroke).frame(height: 1) }
        .onHover { hover = $0 }
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
                          : store.profile == .privateNotes ? "Ask about your materials and case reports…" : "Ask, or tell Holdfast what to do…",
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
                            .foregroundStyle(Theme.onButton)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Theme.button))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(".", modifiers: .command)
                    .help("Stop generating (⌘.)")
                    .accessibilityLabel("Stop generating")
                } else {
                Button { store.runAsk() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(Theme.onButton)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(canSend ? AnyShapeStyle(Theme.button) : AnyShapeStyle(Color.secondary.opacity(0.35))))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend)
                .help("Ask (Return)")
                .accessibilityLabel("Ask")
                }
            }
            .padding(.leading, 18).padding(.trailing, 10).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.canvas))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focused ? Theme.accent.opacity(0.6) : Theme.cardStroke, lineWidth: focused ? 1.5 : 1))
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
                    Section("Model servers") {
                        ForEach([Backend.ollama, .lmStudio, .remote]) { backend in
                            Toggle(backend.title, isOn: Binding(get: { store.backend == backend },
                                set: { if $0 { store.backend = backend } }))
                        }
                    }
                    Divider()
                    Toggle("Show Thinking (slower)", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "showThinking") },
                        set: { UserDefaults.standard.set($0, forKey: "showThinking") }))
                    SettingsLink { Text("More Models…") }
                } label: {
                    Label("Model", systemImage: "cpu").help(store.modelLabel)
                }
                .menuStyle(.borderlessButton)
                .disabled(store.busy != nil || store.asking)
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
                Label(store.backend.locationLabel,
                      systemImage: store.backend != .mlx ? "network" : "lock.fill")
                    .labelStyle(TightLabel())
                    .font(Theme.caption).foregroundStyle(store.backend != .mlx ? Color.orange : Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(store.backend.privacyHelp)
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
                            DisclosureGroup("Reference collections") {
                                PacksSection().padding(.top, 8)
                            }
                            .font(Theme.caption).foregroundStyle(Theme.secondary)
                            .padding(.bottom, 8)
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
                Text("\(count)").foregroundStyle(Theme.secondary)
            }
            .font(Theme.caption.weight(.medium))
            .foregroundStyle(selected ? Theme.accent : Theme.secondary)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.selection : .clear))
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
                KindTile(kind: Theme.kind(of: note), size: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title).font(Theme.callout.weight(.medium)).lineLimit(2)
                        .foregroundStyle(selected ? Theme.accent : Theme.ink)
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
                .fill(selected ? Theme.paper : (hover ? Theme.selection.opacity(0.5) : .clear)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Theme.cardStroke : .clear))
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
                    .buttonStyle(.borderedProminent).tint(Theme.button)
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
    @State private var open = false
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

/// Resizes the browser while reserving enough room for the note.
struct ResizeHandle: View {
    @Binding var width: Double
    var minimum: Double = 260
    var maximum: Double = 900
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
                    width = min(maximum, max(minimum, (start ?? width) + g.translation.width))
                }
                .onEnded { _ in start = nil })
    }
}
