import AppKit
import SwiftUI

// The parts of the notes interface modelled on Obsidian: tabs, the right
// sidebar (outline, backlinks, outgoing links, local graph), note previews,
// and the command palette (⌘P).

// MARK: - Tabs

struct TabBar: View {
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(store.tabs) { t in TabChip(tab: t, active: t.id == store.activeTab) }
                }
                .padding(.horizontal, 6)
            }
            Button { store.quickOpenNewTab = true; store.showQuickOpen = true } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .medium)).frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help("Open a note in a new tab (⌘T)")
            .padding(.trailing, 6)
        }
        .frame(height: 34)
        .background(.background.secondary)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct TabChip: View {
    @EnvironmentObject var store: Store
    var tab: NoteTab
    var active: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: Theme.icon(Theme.kind(of: tab.opened.note)))
                .font(.system(size: 11)).foregroundStyle(active ? Theme.accent : .secondary)
            Text(tab.opened.note.title).font(Theme.callout).lineLimit(1)
                .foregroundStyle(active ? .primary : .secondary)
            Button { store.closeTab(tab.id) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.primary.opacity(hover ? 0.08 : 0)))
            }
            .buttonStyle(.plain)
            .opacity(active || hover ? 1 : 0)
            .help("Close tab (⌘W)")
        }
        .padding(.leading, 10).padding(.trailing, 4).padding(.vertical, 5)
        .frame(maxWidth: 200)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(active ? AnyShapeStyle(.background) : AnyShapeStyle(Color.primary.opacity(hover ? 0.05 : 0))))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(active ? Color.primary.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { store.activeTab = tab.id }
        .onHover { hover = $0 }
        .help(tab.opened.note.relPath)
        .contextMenu {
            Button("Close Tab") { store.closeTab(tab.id) }
            Button("Close Other Tabs") { store.closeOtherTabs(tab.id) }.disabled(store.tabs.count < 2)
            Divider()
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([tab.opened.note.path]) }
        }
    }
}

// MARK: - Right sidebar

enum RightTab: String, CaseIterable, Identifiable {
    case outline, backlinks, links, related, history, graph
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .outline: return "list.bullet.indent"
        case .backlinks: return "arrow.turn.down.right"
        case .links: return "arrow.up.right"
        case .related: return "sparkles"
        case .history: return "clock.arrow.circlepath"
        case .graph: return "point.3.connected.trianglepath.dotted"
        }
    }
    var label: String {
        switch self {
        case .outline: return "Outline"
        case .backlinks: return "Backlinks"
        case .links: return "Outgoing links"
        case .related: return "Related notes"
        case .history: return "History"
        case .graph: return "Local graph"
        }
    }
}

/// Beside the note, as in Obsidian: its outline, the notes that link to it,
/// the notes it links to, and its neighbourhood in the graph.
struct RightPanel: View {
    @EnvironmentObject var store: Store
    var note: Note
    var headings: [MDBlock]
    var current: Int?
    var jump: (Int) -> Void
    @AppStorage("rightTab") private var tab: RightTab = .outline

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(RightTab.allCases) { t in
                    Button { tab = t } label: {
                        Image(systemName: t.icon).font(.system(size: 13))
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .foregroundStyle(tab == t ? Theme.accent : .secondary)
                            .background(RoundedRectangle(cornerRadius: 6).fill(tab == t ? Theme.accent.opacity(0.12) : .clear))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(t.label)
                }
            }
            .padding(8)
            Divider()
            switch tab {
            case .outline:
                OutlinePanel(title: note.title, headings: headings, current: current, jump: jump)
            case .backlinks:
                BacklinksPanel(note: note)
            case .links:
                OutgoingPanel(note: note)
            case .related:
                RelatedPanel(note: note)
            case .history:
                HistoryPanel(note: note)
            case .graph:
                GraphView(compact: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.background.secondary)
    }
}

struct PanelHeader: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(Theme.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.bottom, 4)
    }
}

struct BacklinksPanel: View {
    @EnvironmentObject var store: Store
    var note: Note

    var body: some View {
        let back = (store.links.incoming[note.id] ?? []).compactMap { store.links.byId[$0] }
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                PanelHeader(text: "Linked mentions · \(back.count)")
                if back.isEmpty {
                    Text("No other note links here yet.").font(Theme.callout).foregroundStyle(.secondary).padding(.horizontal, 10)
                }
                ForEach(back, id: \.id) { src in
                    Button { store.openNote(src, newTab: NSEvent.modifierFlags.contains(.command)) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(src.title).font(Theme.callout.weight(.medium)).lineLimit(1)
                            ForEach(store.links.mentions(of: note, in: src).prefix(2), id: \.self) { line in
                                Text(noteInline(line, size: 11.5)).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.035)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverPreview(Opened(note: src, anchor: nil))
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 8)
        }
    }
}

struct OutgoingPanel: View {
    @EnvironmentObject var store: Store
    var note: Note

    var body: some View {
        let out = (store.links.outgoing[note.id] ?? []).compactMap { store.links.byId[$0] }
        let missing = store.links.unresolved[note.id] ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                PanelHeader(text: "Links · \(out.count)")
                ForEach(out, id: \.id) { n in
                    PanelRow(icon: "doc.text", title: n.title, sub: n.relPath) {
                        store.openNote(n, newTab: NSEvent.modifierFlags.contains(.command))
                    }
                    .hoverPreview(Opened(note: n, anchor: nil))
                }
                if !missing.isEmpty {
                    PanelHeader(text: "Not created yet · \(missing.count)").padding(.top, 10)
                    ForEach(missing, id: \.self) { m in
                        PanelRow(icon: "doc.badge.plus", title: m, sub: "Click to create") {
                            store.openLink(URL(string: "holdfast-note:" + (m.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""))!, from: note)
                        }
                        .opacity(0.7)
                    }
                }
            }
            .padding(.vertical, 12).padding(.horizontal, 8)
        }
    }
}

struct PanelRow: View {
    var icon: String
    var title: String
    var sub: String
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(Theme.caption).foregroundStyle(.secondary).frame(width: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(Theme.callout).lineLimit(1)
                    Text(sub).font(Theme.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.primary.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Note previews

/// The part of a note a link points to: the linked section, or the note's
/// opening, rendered as in the reader.
func previewBlocks(_ o: Opened, max: Int = 18) -> [MDBlock] {
    var bs = MarkdownParser.parse(o.note.body)
    if let a = o.anchor, let i = bs.firstIndex(where: { $0.isHeading && ($0.text == a || slug($0.text) == a.lowercased()) }) {
        let level: Int = { if case .heading(let l) = bs[i].kind { return l } else { return 6 } }()
        var end = i + 1
        while end < bs.count {
            if case .heading(let l) = bs[end].kind, l <= level { break }
            end += 1
        }
        bs = Array(bs[i..<end])
    } else if let f = bs.first, case .heading(1) = f.kind {
        bs.removeFirst()
    }
    return Array(bs.prefix(max)).enumerated().map { i, b in var b = b; b.id = i; return b }
}

struct PreviewContent: View {
    var opened: Opened
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(opened.note.title).font(Theme.headline)
                Text(opened.note.relPath + (opened.anchor.map { " › " + $0 } ?? "")).font(Theme.caption).foregroundStyle(.secondary)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(previewBlocks(opened)) { b in MDBlockView(block: b) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// ⌥-click on a link: the note in a card, with buttons to open it.
struct NotePreview: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    var opened: Opened

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreviewContent(opened: opened).frame(height: 360)
            HStack {
                Text("Esc to close").font(Theme.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Open in New Tab") { let o = opened; dismiss(); store.openInNewTab(o) }
                Button("Open") { let o = opened; dismiss(); store.opened = o }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 520)
        .onExitCommand { dismiss() }
    }
}

/// Hover a link for a moment to see the note, as in Obsidian's page preview.
struct HoverPreview: ViewModifier {
    var opened: Opened
    @State private var show = false
    @State private var overSource = false
    @State private var overCard = false
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { h in
                overSource = h
                task?.cancel()
                task = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(h ? 650 : 250))
                    guard !Task.isCancelled else { return }
                    show = overSource || overCard
                }
            }
            .popover(isPresented: $show, arrowEdge: .leading) {
                PreviewContent(opened: opened)
                    .padding(14)
                    .frame(width: 380, height: 300)
                    .onHover { h in
                        overCard = h
                        if !h {
                            task?.cancel()
                            task = Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(250))
                                if !Task.isCancelled && !overSource && !overCard { show = false }
                            }
                        }
                    }
            }
    }
}

extension View {
    func hoverPreview(_ o: Opened) -> some View { modifier(HoverPreview(opened: o)) }
}

// MARK: - Command palette

struct PaletteCommand: Identifiable {
    var id: String { title }
    var title: String
    var icon: String
    var shortcut: String = ""
    var enabled = true
    var run: @MainActor () -> Void
}

@MainActor
func paletteCommands(_ store: Store) -> [PaletteCommand] {
    let note = store.opened?.note
    var cs: [PaletteCommand] = [
        PaletteCommand(title: "Quick Open: find a note", icon: "magnifyingglass", shortcut: "⌘O") { store.quickOpenNewTab = false; store.showQuickOpen = true },
        PaletteCommand(title: "Open a note in a new tab", icon: "plus.square.on.square", shortcut: "⌘T") { store.quickOpenNewTab = true; store.showQuickOpen = true },
        PaletteCommand(title: "New note", icon: "square.and.pencil", shortcut: "⇧⌘N") { store.createNote(near: note) },
        PaletteCommand(title: "Ask a question", icon: "sparkle.magnifyingglass") { store.pane = .ask; store.showList = true },
        PaletteCommand(title: "Add files to the knowledge base…", icon: "tray.and.arrow.down") { store.chooseFilesToAdd() },
        PaletteCommand(title: "Open drop folder", icon: "folder", shortcut: "⇧⌘D") { store.revealDrop() },
        PaletteCommand(title: "Go to Files", icon: "folder", shortcut: "⌥⌘1") { store.pane = .files; store.showList = true },
        PaletteCommand(title: "Go to Graph", icon: "point.3.connected.trianglepath.dotted", shortcut: "⇧⌘G") { store.pane = .graph; store.showList = true },
        PaletteCommand(title: "Go to Library", icon: "books.vertical") { store.pane = .library; store.showList = true },
        PaletteCommand(title: "Go to History", icon: "clock.arrow.circlepath") { store.pane = .history; store.showList = true },
        PaletteCommand(title: "Go to Inbox", icon: "tray") { store.pane = .inbox; store.showList = true },
        PaletteCommand(title: store.showList ? "Hide file list" : "Show file list", icon: "sidebar.left", shortcut: "⇧⌘\\") { store.showList.toggle() },
        PaletteCommand(title: "Rebuild search index", icon: "arrow.clockwise") { store.rebuildIndex() },
        PaletteCommand(title: "Choose vault…", icon: "externaldrive") { store.chooseVault() },
    ]
    if let note {
        cs += [
            PaletteCommand(title: store.editing ? "Switch to reading view" : "Switch to editing view", icon: store.editing ? "book" : "pencil", shortcut: "⌘E") { store.editing.toggle() },
            PaletteCommand(title: "Toggle right sidebar", icon: "sidebar.right", shortcut: "⌥⌘O") {
                UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "showOutline"), forKey: "showOutline")
            },
            PaletteCommand(title: "Back", icon: "chevron.left", shortcut: "⌘[", enabled: !store.backStack.isEmpty) { store.goBack() },
            PaletteCommand(title: "Forward", icon: "chevron.right", shortcut: "⌘]", enabled: !store.forwardStack.isEmpty) { store.goForward() },
            PaletteCommand(title: "Close tab", icon: "xmark", shortcut: "⌘W") { store.closeTab(store.activeTab) },
            PaletteCommand(title: "Close other tabs", icon: "xmark.square", enabled: store.tabs.count > 1) { if let t = store.activeTab { store.closeOtherTabs(t) } },
            PaletteCommand(title: "Show note in Finder", icon: "folder") { NSWorkspace.shared.activateFileViewerSelecting([note.path]) },
            PaletteCommand(title: "Copy wikilink to this note", icon: "link") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString("[[\(note.id)]]", forType: .string)
            },
            PaletteCommand(title: "Copy file path", icon: "doc.on.clipboard") {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(note.path.path, forType: .string)
            },
        ]
    }
    return cs.filter(\.enabled)
}

struct CommandPalette: View {
    @EnvironmentObject var store: Store
    func dismiss() { store.showPalette = false }
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    var results: [PaletteCommand] {
        let all = paletteCommands(store)
        let q = query.lowercased()
        guard !q.isEmpty else { return all }
        // Every word of the query appears in the title, in any order.
        let words = q.split(separator: " ")
        return all.filter { c in words.allSatisfy { c.title.lowercased().contains($0) } }
            .sorted { ($0.title.lowercased().hasPrefix(q) ? 0 : 1) < ($1.title.lowercased().hasPrefix(q) ? 0 : 1) }
    }

    var body: some View {
        let rs = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "command").foregroundStyle(.secondary)
                TextField("Type a command…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 17.5))
                    .focused($focused)
                    .onSubmit { run(rs) }
                    .onChange(of: query) { _, _ in index = 0 }
                    .onKeyPress(.downArrow) { index = min(index + 1, max(rs.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(rs.enumerated()), id: \.element.id) { i, c in
                            PaletteRow(command: c, selected: i == index)
                                .onTapGesture { index = i; run(rs) }
                                .id(i)
                        }
                        if rs.isEmpty {
                            Text("No matching command").font(Theme.callout).foregroundStyle(.secondary).padding(14)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: index) { _, i in proxy.scrollTo(i) }
            }
            .frame(height: 340)
        }
        .frame(width: 560)
        .onAppear { focused = true }
    }

    func run(_ rs: [PaletteCommand]) {
        guard rs.indices.contains(index) else { return }
        let c = rs[index]
        dismiss()
        // After the sheet closes, so commands that open another sheet can.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { c.run() }
    }
}

struct PaletteRow: View {
    var command: PaletteCommand
    var selected: Bool
    var body: some View {
        let fg: Color = selected ? .white : .primary
        let sub: Color = selected ? Color.white.opacity(0.8) : Color.secondary
        HStack(spacing: 10) {
            Image(systemName: command.icon).foregroundStyle(sub).frame(width: 18)
            Text(command.title).font(Theme.callout.weight(.medium)).foregroundStyle(fg)
            Spacer()
            if !command.shortcut.isEmpty {
                Text(command.shortcut).font(Theme.caption.monospaced()).foregroundStyle(sub)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.clear)))
        .contentShape(Rectangle())
    }
}
