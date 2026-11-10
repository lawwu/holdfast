import AppKit
import SwiftUI

// MARK: - Tables (notes by their properties, like Obsidian's Bases)

struct TablesView: View {
    @EnvironmentObject var store: Store
    @State private var type: String?
    @State private var sortKey = "date"
    @State private var ascending = false

    var body: some View {
        let groups = Properties.byType(store.notes)
        let types = groups.keys.sorted { (groups[$0]!.count, $1) > (groups[$1]!.count, $0) }
        let current = type.flatMap { groups[$0] != nil ? $0 : nil } ?? types.first
        VStack(alignment: .leading, spacing: 0) {
            if let current, let rows = groups[current] {
                HStack(spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(types, id: \.self) { t in
                                Button { type = t } label: {
                                    Text("\(t.capitalized) · \(groups[t]!.count)").font(Theme.callout)
                                        .padding(.horizontal, 10).padding(.vertical, 4)
                                        .background(Capsule().fill(t == current ? Theme.accent.opacity(0.16) : Color.primary.opacity(0.05)))
                                        .foregroundStyle(t == current ? Theme.accent : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                Divider()
                PropertyTable(notes: rows, sortKey: $sortKey, ascending: $ascending)
            } else {
                EmptyState(icon: "tablecells", title: "No tables yet",
                           message: "Notes with a \"type\" property (visit, invoice, receipt…) show up here as tables, one column per property. Filing a dropped document gives its new note these properties.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Tables")
    }
}

struct PropertyTable: View {
    @EnvironmentObject var store: Store
    var notes: [Note]
    @Binding var sortKey: String
    @Binding var ascending: Bool
    static let titleWidth: CGFloat = 230
    static let colWidth: CGFloat = 130

    var body: some View {
        let cols = Properties.columns(notes)
        let sorted = notes.sorted { a, b in
            let x = sortKey == "title" ? a.title : (a.meta[sortKey] ?? ""), y = sortKey == "title" ? b.title : (b.meta[sortKey] ?? "")
            if let dx = Double(x), let dy = Double(y) { return ascending ? dx < dy : dx > dy }
            return ascending ? x < y : x > y
        }
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(sorted, id: \.path) { n in
                        Button { store.openNote(n, newTab: NSEvent.modifierFlags.contains(.command)) } label: {
                            HStack(spacing: 0) {
                                Text(n.title).font(Theme.callout.weight(.medium)).lineLimit(1)
                                    .frame(width: Self.titleWidth, alignment: .leading)
                                ForEach(cols, id: \.self) { c in
                                    Text(n.meta[c] ?? "").font(Theme.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                                        .frame(width: Self.colWidth, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .hoverPreview(Opened(note: n, anchor: nil))
                        Divider().padding(.leading, 16)
                    }
                } header: {
                    HStack(spacing: 0) {
                        header("Note", key: "title", width: Self.titleWidth)
                        ForEach(cols, id: \.self) { c in header(c.replacingOccurrences(of: "_", with: " ").capitalized, key: c, width: Self.colWidth) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(.bar)
                }
            }
        }
        .defaultScrollAnchor(.topLeading)
    }

    func header(_ label: String, key: String, width: CGFloat) -> some View {
        Button {
            if sortKey == key { ascending.toggle() } else { sortKey = key; ascending = key == "title" }
        } label: {
            HStack(spacing: 3) {
                Text(label).font(Theme.caption.weight(.semibold)).foregroundStyle(.secondary)
                if sortKey == key { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
            }
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Upcoming (on the Ask screen)

struct UpcomingCard: View {
    @EnvironmentObject var store: Store
    static let shown = 6

    var body: some View {
        if !store.upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("UPCOMING").font(Theme.caption.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
                    Spacer()
                    Text("next \(Upcoming.horizonDays) days").font(Theme.caption).foregroundStyle(.tertiary)
                }
                ForEach(store.upcoming.prefix(Self.shown)) { f in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Button { store.complete(f) } label: {
                            Image(systemName: "circle").font(.system(size: 14.5)).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain).help("Mark done")
                        Button { store.openNote(f.note, newTab: NSEvent.modifierFlags.contains(.command)) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.text).font(Theme.callout).lineLimit(1).foregroundStyle(.primary)
                                Text(f.note.title).font(Theme.caption).foregroundStyle(.tertiary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Text(f.overdue ? "overdue · \(f.due)" : f.due).font(Theme.caption.monospacedDigit())
                            .foregroundStyle(f.overdue ? Color.orange : .secondary)
                    }
                }
                if store.upcoming.count > Self.shown {
                    Text("+\(store.upcoming.count - Self.shown) more").font(Theme.caption).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
        }
    }
}

// MARK: - Inbox: recent filings, rule suggestions, notices

struct NoticeBanner: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if let n = store.notice {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(n).font(Theme.callout)
                Spacer()
                Button { store.notice = nil } label: { Image(systemName: "xmark").font(Theme.caption) }.buttonStyle(.plain).accessibilityLabel("Dismiss")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.08)))
        }
    }
}

struct RuleSuggestionCard: View {
    @EnvironmentObject var store: Store
    var c: Rules.Candidate
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text("You've filed \(c.count) documents from ") + Text(c.from).bold()
                    + Text(c.action == "new" ? " as new notes in " : " to ") + Text(c.target).font(Theme.callout.monospaced()).foregroundColor(Theme.accent)
                    + Text(". Always file them there?")
            } icon: { Image(systemName: "wand.and.stars") }
            .font(Theme.callout)
            HStack(spacing: 8) {
                Button("Make a Rule") { store.acceptRule(c, auto: false) }.buttonStyle(.borderedProminent)
                Button("File Automatically") { store.acceptRule(c, auto: true) }.buttonStyle(.bordered)
                    .help("File without asking. Every filing can still be undone here.")
                Spacer()
                Button("Not Now") { store.dismissRule(c) }.buttonStyle(.link)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.07)))
    }
}

struct RecentFilings: View {
    @EnvironmentObject var store: Store
    static let shown = 8

    var body: some View {
        if !store.filings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("RECENTLY FILED").font(Theme.caption.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
                    Spacer()
                    Button("Filing Rules…") { store.openRules() }.buttonStyle(.link).font(Theme.caption)
                }
                ForEach(store.filings.prefix(Self.shown)) { r in
                    HStack(spacing: 8) {
                        Image(systemName: r.action == "append" ? "text.append" : "doc.badge.plus").font(Theme.caption).foregroundStyle(.secondary).frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.title).font(Theme.callout).lineLimit(1).strikethrough(r.undone)
                            Text(r.target + (r.rule.map { " · rule: \($0)" } ?? "") + " · " + r.date.formatted(.relative(presentation: .named)))
                                .font(Theme.caption).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        Spacer()
                        if r.undone {
                            Text("Undone").font(Theme.caption).foregroundStyle(.tertiary)
                        } else {
                            Button("Open") {
                                if let n = store.notes.first(where: { $0.relPath == r.target }) { store.openNote(n, newTab: false) }
                            }.buttonStyle(.link).font(Theme.caption)
                            Button("Undo") { store.undoFiling(r) }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    .opacity(r.undone ? 0.6 : 1)
                }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Right sidebar: related notes and history

struct RelatedPanel: View {
    @EnvironmentObject var store: Store
    var note: Note
    @State private var related: [RelatedNote] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                PanelHeader(text: "Related notes")
                if loading {
                    ProgressView().controlSize(.small).padding(.horizontal, 10)
                } else if related.isEmpty {
                    Text("Nothing close yet. Related notes come from search embeddings, so the note needs to be indexed.")
                        .font(Theme.callout).foregroundStyle(.secondary).padding(.horizontal, 10)
                }
                ForEach(related) { r in
                    let target = store.notes.first(where: { $0.relPath == r.relPath })
                    let linked = (store.links.outgoing[note.id] ?? []).contains(String(r.relPath.dropLast(r.relPath.hasSuffix(".md") ? 3 : 0)))
                    Button { if let target { store.openNote(target, newTab: NSEvent.modifierFlags.contains(.command)) } } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(target?.title ?? r.title).font(Theme.callout.weight(.medium)).lineLimit(1)
                                Spacer()
                                if linked { Image(systemName: "link").font(Theme.caption2).foregroundStyle(.tertiary).help("Already linked") }
                                Text("\(Int((r.score * 100).rounded()))%").font(Theme.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                            Text(r.relPath).font(Theme.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            Text(r.snippet).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.035)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modifier(OptionalHoverPreview(note: target))
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 8)
        }
        .task(id: note.relPath + "\(store.indexCounts.vectors)") {
            loading = true
            let rel = note.relPath
            related = (try? await Task.detached { try Related.find(rel) }.value) ?? []
            loading = false
        }
    }
}

struct OptionalHoverPreview: ViewModifier {
    var note: Note?
    func body(content: Content) -> some View {
        if let note { content.hoverPreview(Opened(note: note, anchor: nil)) } else { content }
    }
}

struct HistoryPanel: View {
    @EnvironmentObject var store: Store
    var note: Note
    @State private var versions: [Versions.Version] = []
    @State private var viewing: Versions.Version?
    @State private var confirm: Versions.Version?

    static func label(_ reason: String) -> String {
        switch reason {
        case "filing": return "Before a filing"
        case "edit": return "Before an edit"
        case "before-restore": return "Before a restore"
        case "before-undo": return "Before an undo"
        default: return reason
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                PanelHeader(text: "Earlier copies · \(versions.count)")
                if versions.isEmpty {
                    Text("Holdfast keeps a copy before it files into this note or you edit it. None yet.")
                        .font(Theme.callout).foregroundStyle(.secondary).padding(.horizontal, 10)
                }
                ForEach(versions) { v in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(v.date.formatted(date: .abbreviated, time: .shortened)).font(Theme.callout)
                                Text(Self.label(v.reason)).font(Theme.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button(viewing == v ? "Hide" : "View") { viewing = viewing == v ? nil : v }.buttonStyle(.link).font(Theme.caption)
                            Button("Restore") { confirm = v }.buttonStyle(.bordered).controlSize(.small)
                        }
                        if viewing == v, let text = try? String(contentsOf: v.url, encoding: .utf8) {
                            ScrollView {
                                Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 220)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 4)
        }
        .onAppear { versions = Versions.list(note.relPath) }
        .onChange(of: note.body) { versions = Versions.list(note.relPath) }
        .onChange(of: note.path) { versions = Versions.list(note.relPath); viewing = nil }
        .confirmationDialog("Restore this copy?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            presenting: confirm) { v in
            Button("Restore") { store.restore(v, of: note); versions = Versions.list(note.relPath) }
        } message: { v in
            Text("The note goes back to how it was on \(v.date.formatted(date: .abbreviated, time: .shortened)). The current text is kept as a copy first.")
        }
    }
}

// MARK: - Bulk import

struct BulkImportSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var sources: [URL] = []
    @State private var asIs = true
    @State private var folder = "imported"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bulk Import").font(Theme.title2.weight(.semibold))
            HStack {
                Button("Choose Files or Folders…") {
                    let picked = store.chooseBulkImport()
                    sources += picked
                    if folder == "imported", let first = picked.first {
                        folder = "imported/" + slugify(first.deletingPathExtension().lastPathComponent)
                    }
                }
                if !sources.isEmpty { Button("Clear") { sources = [] }.buttonStyle(.link) }
            }
            if !sources.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(sources, id: \.self) { u in
                            Label(u.lastPathComponent, systemImage: u.hasDirectoryPath ? "folder" : "doc").font(Theme.callout).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
            Picker("", selection: $asIs) {
                Text("Bring in as-is").tag(true)
                Text("File each one").tag(false)
            }
            .pickerStyle(.segmented).labelsHidden()
            if asIs {
                Text("Markdown and CSV files are copied. Spreadsheets become CSV tables. Documents, PDFs, mail, slides, ebooks, photos and recordings become Markdown notes of their text (originals stay outside the vault). Zip archives and Evernote, Day One and mailbox exports are opened first. No model is used, so it's fast; recordings still need transcribing.")
                    .font(Theme.callout).foregroundStyle(.secondary)
                HStack {
                    Text("Into folder").font(Theme.callout)
                    TextField("imported/…", text: $folder).textFieldStyle(.roundedBorder)
                }
            } else {
                Text("Every file goes through the drop folder: the model reads it with the folder READMEs and proposes where it belongs, and you approve proposals in groups in the Inbox. Filing rules and duplicate checks apply. Roughly 10–60 seconds per document depending on the model; you can pause anytime.")
                    .font(Theme.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(asIs ? "Import" : "Start Filing") {
                    store.bulkImport(sources, asIs: asIs, folder: folder.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sources.isEmpty || (asIs && folder.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}

/// Progress of an import or of the filing queue, with pause for filing.
struct ImportProgressBar: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if let p = store.importProgress {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(p.total == 0 ? (store.jobTitle == "Importing" ? "Opening files…" : "Getting ready…")
                         : "\(store.jobTitle) \(min(p.done + 1, p.total)) of \(p.total)").font(Theme.callout.weight(.medium))
                    Spacer()
                    Text(p.file).font(Theme.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    if store.jobTitle != "Importing" { Button("Stop") { store.stopJob() }.buttonStyle(.bordered).controlSize(.small) }
                }
                if p.total > 0 { ProgressView(value: Double(p.done), total: Double(p.total)) } else { ProgressView().progressViewStyle(.linear) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.06)))
        } else if store.queueDone + store.queueLeft > 1 {
            let total = store.queueDone + store.queueLeft
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(store.dropPaused ? "Filing paused · \(store.queueDone) of \(total)" : "Filing \(min(store.queueDone + 1, total)) of \(total)")
                        .font(Theme.callout.weight(.medium))
                    Spacer()
                    Button(store.dropPaused ? "Resume" : "Pause") { store.pauseFiling(!store.dropPaused) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                ProgressView(value: Double(store.queueDone), total: Double(total))
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accent.opacity(0.06)))
        }
    }
}

/// Proposals that go to the same place, approved together.
struct FilingGroupHeader: View {
    @EnvironmentObject var store: Store
    var place: String
    var items: [Note]
    var body: some View {
        HStack {
            Image(systemName: "square.stack.3d.up").foregroundStyle(.secondary)
            Text("\(items.count) proposals → ") + Text(place).font(Theme.callout.monospaced()).foregroundColor(Theme.accent)
            Spacer()
            Button("File All \(items.count)") { store.approveAll(items) }.buttonStyle(.borderedProminent).tint(.green).controlSize(.small)
        }
        .font(Theme.callout)
        .padding(.top, 6)
    }
}

/// The place a filing proposal goes: its note, or for a new note its folder.
func filingPlace(_ n: Note) -> String? {
    guard n.meta["kind"] == "filing", let t = n.meta["target"] else { return nil }
    return n.meta["action"] == "new" ? (t as NSString).deletingLastPathComponent + "/" : t
}

// MARK: - Knowledge packs (Library)

struct PacksSection: View {
    @EnvironmentObject var store: Store
    @State private var packs: [PackManifest] = Packs.installed()
    @State private var enabled = Packs.enabled()
    @State private var counts: [String: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("KNOWLEDGE PACKS").font(Theme.caption.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
                Spacer()
                Button("Show in Finder") {
                    try? FileManager.default.createDirectory(at: Packs.dir, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(Packs.dir)
                }.buttonStyle(.link).font(Theme.caption)
            }
            if packs.isEmpty {
                Text("Reference collections (a Bible, a wiki) that Ask can quote beside your notes. None installed.")
                    .font(Theme.callout).foregroundStyle(.secondary)
            }
            ForEach(packs) { m in
                HStack(alignment: .top, spacing: 10) {
                    Toggle("", isOn: Binding(get: { enabled.contains(m.id) }, set: { on in
                        Packs.setEnabled(m.id, on); enabled = Packs.enabled()
                    })).toggleStyle(.switch).labelsHidden().controlSize(.small).accessibilityLabel("Use \(m.name)")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name).font(Theme.callout.weight(.semibold))
                        Text(m.description).font(Theme.caption).foregroundStyle(.secondary).lineLimit(2)
                        Text("\(m.license) · \(m.attribution)").font(Theme.caption2).foregroundStyle(.tertiary).lineLimit(2)
                    }
                    Spacer()
                    if let n = counts[m.id] {
                        Text("\(n) passages").font(Theme.caption.monospacedDigit()).foregroundStyle(.secondary)
                    } else {
                        Button("Index") { store.indexPack(m.id) }.buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: store.indexCounts.chunks) { refresh() }
        .onChange(of: store.packsVersion) { refresh() }
    }

    func refresh() {
        packs = Packs.installed()
        enabled = Packs.enabled()
        counts = Dictionary(uniqueKeysWithValues: packs.compactMap { m in Packs.count(m.id).map { (m.id, $0.chunks) } })
    }
}

// MARK: - Earlier turns of a conversation

struct TurnView: View {
    @EnvironmentObject var store: Store
    var entry: HistoryEntry
    @State private var showSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuestionHeader(text: entry.question)
            if let steps = entry.steps, !steps.isEmpty { StepsList(steps: steps, running: false) }
            MarkdownBlocks(text: entry.answer)
            HStack(spacing: 12) {
                if !entry.sources.isEmpty {
                    Button(showSources ? "Hide sources" : "\(entry.sources.count) sources") { showSources.toggle() }.buttonStyle(.link).font(Theme.caption)
                }
                if let r = entry.route { Label(r, systemImage: "arrow.triangle.branch").font(Theme.caption).foregroundStyle(.tertiary) }
            }
            if showSources {
                ForEach(Array(entry.sources.enumerated()), id: \.offset) { i, s in
                    Button { store.open(s.chunk) } label: {
                        Text("[\(i + 1)] \(s.title) — \(s.anchor)").font(Theme.caption).lineLimit(1)
                    }.buttonStyle(.link)
                }
            }
        }
    }
}

/// A past conversation, read-only, opened while another one is generating.
struct ConversationReader: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var thread: UUID

    var body: some View {
        let turns = store.history.filter { $0.thread == thread }.sorted { $0.date < $1.date }
        VStack(spacing: 0) {
            HStack {
                Text(turns.first?.question ?? "Conversation").font(Theme.headline).lineLimit(1)
                Spacer()
                Button("Continue This Conversation") {
                    if let last = turns.last { dismiss(); store.openHistory(last) }
                }
                .disabled(store.busy != nil)
                .help(store.busy != nil ? "Available when the current answer finishes" : "Open it in Ask to ask a follow-up")
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(turns) { t in
                        TurnView(entry: t)
                        Divider()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 480, idealHeight: 640)
    }
}


/// A panel over the window that closes on a click outside it (or Esc, handled by its content).
struct FloatingPanel<Content: View>: View {
    var close: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
            content
                .frame(width: 560)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
                .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
                .padding(.top, 70)
        }
        .transition(.opacity)
    }
}

// MARK: - A model on another Mac (setup)

struct RemoteSetupSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var address = UserDefaults.standard.string(forKey: "remoteURL") ?? ""
    @State private var models: [String] = []
    @State private var model = UserDefaults.standard.string(forKey: "remoteModel") ?? ""
    @State private var status: String?
    @State private var ok = false
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Use a Model on Another Mac").font(Theme.title2)
            Text("Your vault, its index and search stay on this Mac. The other Mac's model receives each question with the passages search found, the conversation so far, folder READMEs, Research's note reads and table results, documents you drop for filing, and note pairs when suggesting links. Counseling notes never leave this Mac: anything that involves them is answered here. Run LM Studio (or mlx_lm.server, or Ollama) there with its server on, and use its Tailscale name so the traffic is encrypted.")
                .font(Theme.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("http://studio:1234", text: $address).textFieldStyle(.roundedBorder).font(Theme.body)
                Button(checking ? "Checking…" : "Connect") { Task { await check() } }.disabled(checking || address.isEmpty)
            }
            Text("LM Studio uses port 1234, mlx_lm.server 8080, Ollama 11434.").font(Theme.caption).foregroundStyle(.tertiary)
            if let status {
                Label(status, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(ok ? Color.green : Color.orange).font(Theme.callout)
            }
            if !models.isEmpty {
                Picker("Model", selection: $model) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Use This Model") {
                    UserDefaults.standard.set(address.trimmingCharacters(in: .whitespaces), forKey: "remoteURL")
                    UserDefaults.standard.set(model, forKey: "remoteModel")
                    store.backend = .remote
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!ok || model.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 540)
        .task { if !address.isEmpty { await check() } }
    }

    func check() async {
        checking = true
        defer { checking = false }
        var a = address.trimmingCharacters(in: .whitespaces)
        if !a.contains("://") { a = "http://" + a; address = a }
        guard let u = URL(string: a), u.host != nil else { ok = false; status = "That doesn't look like an address."; return }
        do {
            let ms = try await Remote.ping(u)
            models = try await Remote.models(at: u)
            if !models.contains(model) { model = models.first ?? "" }
            ok = true
            let tailnet = u.host!.hasSuffix(".ts.net") || u.host!.hasPrefix("100.") || !u.host!.contains(".")
            status = "Connected to \(u.host!) · \(ms) ms · \(models.count) model\(models.count == 1 ? "" : "s")"
                + (u.scheme == "https" || tailnet ? "" : " · not a Tailscale address: traffic on your network isn't encrypted")
        } catch {
            ok = false
            status = "Couldn't reach \(u.host ?? a): is its server on, and is this Mac on the same network or tailnet?"
        }
    }
}


/// A job the router recognised, waiting for a click (jobs never start from a sentence by themselves).
struct JobConfirmCard: View {
    var title: String
    var detail: String
    var start: () -> Void
    var cancel: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "link.badge.plus").font(.title3).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Theme.headline)
                Text(detail).font(Theme.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Start", action: start).buttonStyle(.borderedProminent)
                    Button("Cancel", action: cancel).buttonStyle(.bordered)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .card(padding: 14)
    }
}

/// Shown until the answer model is downloaded: what to do first.
/// No `.fixedSize(vertical:)` on the text in this card or JobConfirmCard: outside a scroll view it
/// left the whole window blank (2026-11-07), so the text wraps on its own here.
struct FirstRunCard: View {
    @EnvironmentObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle").font(.title3).foregroundStyle(Theme.accent)
                Text("Download a model to start").font(Theme.headline)
            }
            Text("Holdfast answers with a model that runs on this Mac. This is the one that suits it best; others, and the search models, are in Settings.")
                .font(Theme.callout).foregroundStyle(.secondary)
            RecommendationRows()
            SettingsLink { Text("Open Settings…") }
        }
        .card(padding: 14)
    }
}

/// "Recommended for this Mac" with a faster alternative when there is one, each with Download, Use or In use.
struct RecommendationRows: View {
    @EnvironmentObject var store: Store
    var body: some View {
        if let p = Recommend.pick() {
            VStack(alignment: .leading, spacing: 10) {
                row(p.best, label: String(format: "Recommended for this Mac (%.0f GB)", p.ramGB), why: p.why)
                if let f = p.faster, let w = p.fasterWhy { row(f, label: "Faster", why: w) }
                Text("Scores from Holdfast's household eval, measured on an \(ModelCatalog.measuredOn).")
                    .font(Theme.caption2).foregroundStyle(.tertiary)
            }
        } else {
            Text("None of the measured models fits this Mac's memory well; a model on another Mac can answer instead.")
                .font(Theme.callout).foregroundStyle(.secondary)
        }
    }

    func row(_ m: ModelScore, label: String, why: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased()).font(Theme.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(Theme.accent)
                Text("\(m.name) · \(m.detail)").font(Theme.callout.weight(.semibold))
                Text(why).font(Theme.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            action(m)
        }
    }

    @ViewBuilder func action(_ m: ModelScore) -> some View {
        if let f = store.downloads[m.repo] {
            HStack(spacing: 6) {
                ProgressView(value: f).frame(width: 70)
                Text(String(format: "%.0f%%", f * 100)).font(Theme.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        } else if store.isDownloaded(m.repo) {
            if store.backend == .mlx && store.mlxRepo == m.repo {
                Pill(text: "In use", icon: "checkmark", color: .green)
            } else {
                Button("Use") { store.selectMLX(m.repo) }.controlSize(.small)
            }
        } else {
            Button(String(format: "Download %.0f GB", m.sizeGB)) { store.downloadRepo(m.repo) { store.selectMLX(m.repo) } }
                .controlSize(.small)
                .help("From huggingface.co/\(m.repo)")
        }
    }
}
