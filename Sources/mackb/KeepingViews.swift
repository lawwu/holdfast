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
                                    Text("\(t.capitalized) · \(groups[t]!.count)").font(.callout)
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
                                Text(n.title).font(.callout.weight(.medium)).lineLimit(1)
                                    .frame(width: Self.titleWidth, alignment: .leading)
                                ForEach(cols, id: \.self) { c in
                                    Text(n.meta[c] ?? "").font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
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
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if sortKey == key { Image(systemName: ascending ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary) }
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
                    Text("UPCOMING").font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
                    Spacer()
                    Text("next \(Upcoming.horizonDays) days").font(.caption).foregroundStyle(.tertiary)
                }
                ForEach(store.upcoming.prefix(Self.shown)) { f in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Button { store.complete(f) } label: {
                            Image(systemName: "circle").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain).help("Mark done")
                        Button { store.openNote(f.note, newTab: NSEvent.modifierFlags.contains(.command)) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.text).font(.callout).lineLimit(1).foregroundStyle(.primary)
                                Text(f.note.title).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Text(f.overdue ? "overdue · \(f.due)" : f.due).font(.caption.monospacedDigit())
                            .foregroundStyle(f.overdue ? Color.orange : .secondary)
                    }
                }
                if store.upcoming.count > Self.shown {
                    Text("+\(store.upcoming.count - Self.shown) more").font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: 560)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.035)))
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
                Text(n).font(.callout)
                Spacer()
                Button { store.notice = nil } label: { Image(systemName: "xmark").font(.caption) }.buttonStyle(.plain)
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
                    + Text(c.action == "new" ? " as new notes in " : " to ") + Text(c.target).font(.callout.monospaced()).foregroundColor(Theme.accent)
                    + Text(". Always file them there?")
            } icon: { Image(systemName: "wand.and.stars") }
            .font(.callout)
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
                    Text("RECENTLY FILED").font(.caption.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
                    Spacer()
                    Button("Filing Rules…") { store.openRules() }.buttonStyle(.link).font(.caption)
                }
                ForEach(store.filings.prefix(Self.shown)) { r in
                    HStack(spacing: 8) {
                        Image(systemName: r.action == "append" ? "text.append" : "doc.badge.plus").font(.caption).foregroundStyle(.secondary).frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.title).font(.callout).lineLimit(1).strikethrough(r.undone)
                            Text(r.target + (r.rule.map { " · rule: \($0)" } ?? "") + " · " + r.date.formatted(.relative(presentation: .named)))
                                .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        Spacer()
                        if r.undone {
                            Text("Undone").font(.caption).foregroundStyle(.tertiary)
                        } else {
                            Button("Open") {
                                if let n = store.notes.first(where: { $0.relPath == r.target }) { store.openNote(n, newTab: false) }
                            }.buttonStyle(.link).font(.caption)
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
                        .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 10)
                }
                ForEach(related) { r in
                    let target = store.notes.first(where: { $0.relPath == r.relPath })
                    let linked = (store.links.outgoing[note.id] ?? []).contains(String(r.relPath.dropLast(r.relPath.hasSuffix(".md") ? 3 : 0)))
                    Button { if let target { store.openNote(target, newTab: NSEvent.modifierFlags.contains(.command)) } } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(target?.title ?? r.title).font(.callout.weight(.medium)).lineLimit(1)
                                Spacer()
                                if linked { Image(systemName: "link").font(.caption2).foregroundStyle(.tertiary).help("Already linked") }
                                Text("\(Int((r.score * 100).rounded()))%").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                            Text(r.relPath).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            Text(r.snippet).font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
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
                        .font(.callout).foregroundStyle(.secondary).padding(.horizontal, 10)
                }
                ForEach(versions) { v in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(v.date.formatted(date: .abbreviated, time: .shortened)).font(.callout)
                                Text(Self.label(v.reason)).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button(viewing == v ? "Hide" : "View") { viewing = viewing == v ? nil : v }.buttonStyle(.link).font(.caption)
                            Button("Restore") { confirm = v }.buttonStyle(.bordered).controlSize(.small)
                        }
                        if viewing == v, let text = try? String(contentsOf: v.url, encoding: .utf8) {
                            ScrollView {
                                Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
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
