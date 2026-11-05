import AppKit
import SwiftUI

/// A note, Obsidian-style: a reading view (rendered Markdown, the cited
/// section highlighted, links that open in the app) and an editing view (the
/// styled source editor, saved as you type). Backlinks and outgoing links
/// sit under the note. ⌘E switches modes.
struct NoteView: View {
    @EnvironmentObject var store: Store
    var opened: Opened

    @State private var draft = ""
    @State private var draftPath: URL?
    @State private var saveState: SaveState = .saved
    @State private var saveTask: Task<Void, Never>?
    /// The outline (table of contents) beside the reader; remembered across notes.
    @AppStorage("showOutline") private var showOutline = true
    /// The first block on screen, so the outline can mark where you are.
    @State private var topVisible = -1

    enum SaveState { case saved, editing, failed(String) }

    var note: Note { opened.note }

    var blocks: [MDBlock] {
        var bs = MarkdownParser.parse(note.body)
        // The title is in the header; drop a leading H1 that repeats it.
        if let f = bs.first, case .heading(1) = f.kind, f.text == note.title { bs.removeFirst() }
        // ids double as indices (the anchor highlight relies on it).
        return bs.enumerated().map { i, b in var b = b; b.id = i; return b }
    }

    func isAnchor(_ b: MDBlock) -> Bool {
        guard let a = opened.anchor, a != note.title else { return false }
        if b.isHeading { return b.text == a || slug(b.text) == a.lowercased() }
        return b.text.hasPrefix("[\(a)]") || b.text.hasPrefix("**\(a)**")
    }

    var isRecording: Bool {
        guard let src = note.meta["source"] else { return false }
        return ["recording", "video"].contains(note.meta["kind"] ?? "") && FileManager.default.fileExists(atPath: src)
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.editing {
                MarkdownEditor(text: $draft, notes: store.notes) { url in
                    let mods = NSEvent.modifierFlags
                    if mods.contains(.option) { store.preview = store.resolveLink(url, from: note) }
                    else { store.openLink(url, from: note, newTab: mods.contains(.command)) }
                }
                    .onChange(of: draft) { _, new in scheduleSave(new) }
                EditorStatusBar(state: saveState, text: draft, path: note.relPath)
            } else {
                reader
            }
        }
        .navigationTitle(note.title)
        .onAppear { loadDraft() }
        .onChange(of: opened.note.path) { _, _ in flush(); loadDraft() }
        .onChange(of: store.editing) { _, editing in if editing { loadDraft() } else { flush() } }
        .onDisappear { flush() }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { store.showList.toggle() } label: {
                    Label(store.showList ? "Hide File List" : "Show File List",
                          systemImage: store.showList ? "rectangle.righthalf.inset.filled" : "rectangle.split.2x1")
                }
                .help(store.showList ? "Hide the file list to read the note wide (⇧⌘\\)" : "Show the file list again (⇧⌘\\)")
                Button { store.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(store.backStack.isEmpty)
                    .help(store.backStack.last.map { "Back to \($0.note.title) (⌘[)" } ?? "Back (⌘[)")
                Button { store.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                    .disabled(store.forwardStack.isEmpty)
                    .help(store.forwardStack.last.map { "Forward to \($0.note.title) (⌘])" } ?? "Forward (⌘])")
            }
            ToolbarItemGroup {
                Toggle(isOn: $showOutline) { Label("Right Sidebar", systemImage: "sidebar.right") }
                    .disabled(store.editing)
                    .help("Outline, backlinks, links and local graph (⌥⌘O)")
                    .keyboardShortcut("o", modifiers: [.command, .option])
                Picker("Mode", selection: $store.editing) {
                    Label("Reading", systemImage: "book").tag(false)
                    Label("Editing", systemImage: "pencil").tag(true)
                }
                .pickerStyle(.segmented)
                .help("Switch between reading and editing (⌘E)")
                Button { NSWorkspace.shared.activateFileViewerSelecting([note.path]) } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .help("Show the Markdown file in Finder")
                Button { store.opened = nil } label: { Label("Close", systemImage: "xmark") }
                    .help("Close the note")
            }
        }
    }

    // MARK: reading

    var reader: some View {
        let bs = blocks
        let anchorIdx = bs.firstIndex(where: isAnchor)
        let kind = Theme.kind(of: note)
        let outline = bs.filter { b in if case .heading(let l) = b.kind { return l <= 4 } else { return false } }
        return ScrollViewReader { proxy in
          HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    NoteHeader(note: note, kind: kind).id(-1)
                    Divider().padding(.bottom, 6)
                    ForEach(bs) { b in
                        let inAnchor = anchorIdx.map { i in
                            b.id == i || (bs[i].isHeading && b.id > i && !bs[(i + 1)...b.id].contains { $0.isHeading })
                        } ?? false
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if let t = b.time, isRecording {
                                Button { store.play(note, at: t) } label: {
                                    Image(systemName: "play.circle.fill").foregroundStyle(Theme.accent)
                                }
                                .buttonStyle(.plain).help("Play from here")
                            }
                            MDBlockView(block: b)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, inAnchor ? 4 : 0)
                        .padding(.leading, inAnchor ? 12 : 0)
                        .padding(.trailing, inAnchor ? 8 : 0)
                        .background(alignment: .leading) {
                            if inAnchor {
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(Theme.accent.opacity(0.08))
                                    Rectangle().fill(Theme.gradient).frame(width: 3)
                                }
                            }
                        }
                        .id(b.id)
                    }
                    LinksFooter(note: note).padding(.top, 28)
                }
                .scrollTargetLayout()
                .padding(.horizontal, 36).padding(.vertical, 28)
                .frame(maxWidth: 800, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onScrollTargetVisibilityChange(idType: Int.self, threshold: 0.01) { ids in
                topVisible = ids.min() ?? -1
            }
            if showOutline {
                Divider()
                RightPanel(note: note, headings: outline,
                           current: outline.last { $0.id <= max(topVisible, 0) }?.id ?? (topVisible <= 0 ? nil : outline.first?.id)) { id in
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .top) }
                }
                .frame(width: 250)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
          }
          .animation(.easeOut(duration: 0.18), value: showOutline)
            .onAppear { if let i = anchorIdx { proxy.scrollTo(i, anchor: .top) } }
            .onChange(of: opened) { _, _ in
                if let i = blocks.firstIndex(where: isAnchor) { withAnimation { proxy.scrollTo(i, anchor: .top) } }
                else { proxy.scrollTo(-1, anchor: .top) }
            }
        }
    }

    // MARK: editing

    func loadDraft() {
        guard store.editing else { return }
        if draftPath != note.path || saveState.isSaved {
            draft = (try? String(contentsOf: note.path, encoding: .utf8)) ?? ""
            draftPath = note.path
            saveState = .saved
        }
    }

    func scheduleSave(_ text: String) {
        guard draftPath == note.path else { return }
        if (try? String(contentsOf: note.path, encoding: .utf8)) == text { return }
        saveState = .editing
        saveTask?.cancel()
        let path = note.path
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            save(text, to: path)
        }
    }

    func flush() {
        guard case .editing = saveState, let p = draftPath else { return }
        saveTask?.cancel()
        save(draft, to: p)
    }

    func save(_ text: String, to path: URL) {
        do {
            try store.saveNote(at: path, text: text)
            saveState = .saved
        } catch {
            saveState = .failed("\(error)")
        }
    }
}

extension NoteView.SaveState {
    var isSaved: Bool { if case .saved = self { return true } else { return false } }
}

/// GitHub-style heading anchor: "Where to look" → "where-to-look".
func slug(_ heading: String) -> String {
    heading.lowercased()
        .replacingOccurrences(of: #"[^\p{L}\p{N}\s-]"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: #"\s"#, with: "-", options: .regularExpression)
}

struct NoteHeader: View {
    var note: Note
    var kind: String

    var chips: [String] {
        var out: [String] = []
        if let c = note.meta["case"] { out.append(c) }
        if let s = note.meta["session"] { out.append("Session \(s)") }
        if let k = note.meta["session_kind"] { out.append(k) }
        if let d = note.meta["date"] { out.append(d) }
        return out
    }

    /// Frontmatter shown as properties, like Obsidian's (minus what the header shows).
    var properties: [(String, String)] {
        let hidden: Set = ["title", "kind", "case", "session", "session_kind", "date", "doc_type"]
        return note.meta.filter { !hidden.contains($0.key) }.sorted { $0.key < $1.key }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Pill(text: note.domain ?? Theme.label(kind).replacingOccurrences(of: "s$", with: "", options: .regularExpression),
                     icon: note.domain == nil ? Theme.icon(kind) : "folder", color: note.domain.map(domainColor) ?? Theme.color(kind))
                ForEach(chips, id: \.self) { Pill(text: $0) }
                Spacer()
                Text(note.relPath).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
            }
            Text(note.title)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
            if !properties.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    ForEach(properties.prefix(10), id: \.0) { k, v in
                        GridRow {
                            Text(k).font(.caption).foregroundStyle(.secondary)
                            Text(v).font(.caption).lineLimit(2)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
            }
        }
        .padding(.bottom, 4)
    }
}

/// Backlinks ("linked mentions", with the linking line) and outgoing links.
struct LinksFooter: View {
    @EnvironmentObject var store: Store
    var note: Note
    @State private var showBack = true
    @State private var showOut = false

    var body: some View {
        let back = (store.links.incoming[note.id] ?? []).compactMap { store.links.byId[$0] }
        let out = (store.links.outgoing[note.id] ?? []).compactMap { store.links.byId[$0] }
        let missing = store.links.unresolved[note.id] ?? []
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            DisclosureGroup(isExpanded: $showBack) {
                if back.isEmpty {
                    Text("No other note links here yet.").font(.callout).foregroundStyle(.secondary).padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(back, id: \.id) { src in
                            Button { store.openNote(src) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.turn.down.right").font(.caption).foregroundStyle(Theme.accent)
                                        Text(src.title).font(.callout.weight(.semibold))
                                        Text(src.relPath).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                    ForEach(store.links.mentions(of: note, in: src).prefix(2), id: \.self) { line in
                                        Text(noteInline(line, size: 12.5)).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(2)
                                            .padding(.leading, 20)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.035)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .hoverPreview(Opened(note: src, anchor: nil))
                        }
                    }
                    .padding(.top, 6)
                }
            } label: {
                Label("Linked mentions · \(back.count)", systemImage: "link").font(.headline)
            }
            DisclosureGroup(isExpanded: $showOut) {
                FlowChips(items: out.map { ($0.id, $0.title) } + missing.map { ("?" + $0, $0) }) { id in
                    if id.hasPrefix("?") {
                        store.openLink(URL(string: "mackb-note:" + (String(id.dropFirst()).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""))!, from: note)
                    } else if let n = store.links.byId[id] { store.openNote(n) }
                }
                .padding(.top, 6)
            } label: {
                Label("Links from this note · \(out.count)\(missing.isEmpty ? "" : " (+\(missing.count) not yet created)")",
                      systemImage: "arrow.up.right").font(.headline)
            }
        }
    }
}

/// Wrapping row of link chips.
struct FlowChips: View {
    var items: [(id: String, label: String)]
    var onTap: (String) -> Void
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.id) { it in
                Button { onTap(it.id) } label: {
                    Text(it.label).font(.caption.weight(.medium))
                        .foregroundStyle(it.id.hasPrefix("?") ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(it.id.hasPrefix("?") ? Color.primary.opacity(0.05) : Theme.accent.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .help(it.id.hasPrefix("?") ? "Not created yet — click to create it" : it.id)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

struct EditorStatusBar: View {
    var state: NoteView.SaveState
    var text: String
    var path: String
    var body: some View {
        HStack(spacing: 14) {
            switch state {
            case .saved: Label("Saved", systemImage: "checkmark.circle").foregroundStyle(.green)
            case .editing: Label("Editing…", systemImage: "pencil").foregroundStyle(.secondary)
            case .failed(let e): Label("Not saved: \(e)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            Spacer()
            Text("\(text.split { $0.isWhitespace || $0.isNewline }.count) words")
            Text(path).lineLimit(1).truncationMode(.head)
        }
        .labelStyle(TightLabel())
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(.bar)
    }
}

/// Top-level folders of the vault, alphabetical; set on load so each folder
/// gets its own colour (hashing names gave several folders the same one).
nonisolated(unsafe) var vaultDomains: [String] = []

/// A distinct colour per top-level folder, for chips, the file tree and the graph.
func domainColor(_ d: String) -> Color {
    let palette: [Color] = [.blue, .orange, .green, .pink, Theme.accent, .teal, .yellow, .red, .brown, .mint, .indigo, .cyan]
    if let i = vaultDomains.firstIndex(of: d) { return palette[i % palette.count] }
    var h: UInt32 = 2166136261
    for b in d.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
    return palette[Int(h % UInt32(palette.count))]
}

/// Table of contents for the open note: its headings, indented by level, with
/// the section on screen marked. Click to jump.
struct OutlinePanel: View {
    var title: String
    var headings: [MDBlock]
    var current: Int?
    var jump: (Int) -> Void

    var minLevel: Int {
        headings.compactMap { if case .heading(let l) = $0.kind { return l } else { return nil } }.min() ?? 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                Text(headings.isEmpty ? "NO HEADINGS" : "ON THIS PAGE").font(.caption2.weight(.semibold)).tracking(0.6).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).padding(.bottom, 6)
                Button { jump(-1) } label: {
                    Text(title).font(.callout.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ForEach(headings) { h in OutlineRow(heading: h, indent: level(h) - minLevel, active: h.id == current) { jump(h.id) } }
            }
            .padding(.vertical, 16).padding(.horizontal, 8)
        }
    }

    func level(_ b: MDBlock) -> Int { if case .heading(let l) = b.kind { return l } else { return 1 } }
}

struct OutlineRow: View {
    var heading: MDBlock
    var indent: Int
    var active: Bool
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Rectangle().fill(active ? Theme.accent : .clear).frame(width: 2)
                Text(plain(heading.text))
                    .font(indent == 0 ? .callout.weight(.medium) : .callout)
                    .foregroundStyle(active ? Theme.accent : (indent == 0 ? .primary : .secondary))
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .padding(.leading, 8 + CGFloat(indent) * 12)
                    .padding(.vertical, 4)
                Spacer(minLength: 0)
            }
            .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Color.primary.opacity(0.05) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(plain(heading.text))
    }

    /// Heading text without Markdown marks.
    func plain(_ s: String) -> String {
        s.replacingOccurrences(of: #"\[\[([^\]|]+\|)?([^\]]+)\]\]"#, with: "$2", options: .regularExpression)
            .replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[*_`]"#, with: "", options: .regularExpression)
    }
}
