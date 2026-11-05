import AppKit
import SwiftUI

/// A folder or note in the Files tree.
struct FileNode: Identifiable, Hashable {
    var id: String       // vault-relative path ("" for the root)
    var name: String
    var note: Note?
    var children: [FileNode]?

    static func == (a: FileNode, b: FileNode) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    /// Builds the tree from vault-relative paths: folders first, then notes,
    /// each alphabetical (README first, as on GitHub).
    static func tree(_ notes: [Note]) -> [FileNode] {
        final class Dir {
            var dirs: [String: Dir] = [:]
            var notes: [Note] = []
        }
        let root = Dir()
        for n in notes {
            var d = root
            let parts = n.relPath.split(separator: "/").map(String.init)
            for p in parts.dropLast() {
                if d.dirs[p] == nil { d.dirs[p] = Dir() }
                d = d.dirs[p]!
            }
            d.notes.append(n)
        }
        func build(_ d: Dir, _ prefix: String) -> [FileNode] {
            let folders = d.dirs.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { k in
                FileNode(id: prefix + k + "/", name: k, note: nil, children: build(d.dirs[k]!, prefix + k + "/"))
            }
            let files = d.notes.sorted {
                let a = $0.name.lowercased() == "readme", b = $1.name.lowercased() == "readme"
                return a != b ? a : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }.map { FileNode(id: $0.relPath, name: $0.name, note: $0, children: nil) }
            return folders + files
        }
        return build(root, "")
    }
}

struct FilesView: View {
    @EnvironmentObject var store: Store
    @State private var filter = ""

    var matches: [Note] {
        store.notes.filter { n in
            filter.split(separator: " ").allSatisfy { w in
                n.relPath.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || n.title.range(of: w, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                SearchField(text: $filter, placeholder: "Filter files…")
                Button { store.createNote(near: store.opened?.note) } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .help("New note next to the open one (⇧⌘N)")
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            if store.notes.isEmpty {
                EmptyState(icon: "folder", title: "No notes", message: "Choose a folder of Markdown notes as the vault, or create one with ⇧⌘N.")
            } else if !filter.isEmpty {
                List(matches, id: \.path) { n in FileRow(name: n.title, detail: n.relPath, note: n) }
                    .listStyle(.inset)
            } else {
                List {
                    OutlineGroup(FileNode.tree(store.notes), children: \.children) { node in
                        if let n = node.note {
                            FileRow(name: n.name, detail: nil, note: n)
                        } else {
                            Label(node.name, systemImage: "folder.fill")
                                .foregroundStyle(.primary)
                                .labelStyle(FolderLabel(color: node.id.split(separator: "/").first.map { domainColor(String($0)) } ?? Theme.accent))
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            HStack {
                Text("\(store.notes.count) notes · \(store.links.edgeCount) links").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quick Open ⌘O") { store.showQuickOpen = true }.buttonStyle(.link).font(.caption)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .navigationTitle("Files")
    }
}

struct FolderLabel: LabelStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(color.opacity(0.85))
            configuration.title.font(.callout.weight(.medium))
        }
    }
}

struct FileRow: View {
    @EnvironmentObject var store: Store
    var name: String
    var detail: String?
    var note: Note

    var body: some View {
        let selected = store.opened?.note.path == note.path
        Button { store.openNote(note) } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").foregroundStyle(selected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.callout).lineLimit(1)
                    if let detail { Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
                }
                Spacer(minLength: 0)
                let back = store.links.incoming[note.id]?.count ?? 0
                if back > 0 {
                    Text("\(back)").font(.caption2.weight(.medium)).foregroundStyle(.tertiary)
                        .help("\(back) notes link here")
                }
            }
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selected ? RoundedRectangle(cornerRadius: 6).fill(Theme.accent.opacity(0.14)).padding(.horizontal, 6) : nil)
        .contextMenu {
            Button("Open in Editing View") { store.editing = true; store.openNote(note) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.path]) }
            Button("Copy Wikilink") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("[[\(note.id)]]", forType: .string)
            }
        }
    }
}

// MARK: - Quick Open (⌘O)

/// Obsidian's quick switcher: type part of a title or path, Return opens.
struct QuickOpen: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool

    /// Subsequence match on title, then path; title prefixes and recent notes rank first.
    var results: [Note] {
        let q = query.lowercased().replacingOccurrences(of: " ", with: "")
        guard !q.isEmpty else {
            // Most-linked notes first: usually the hubs you want.
            return Array(store.notes.sorted {
                (store.links.incoming[$0.id]?.count ?? 0) > (store.links.incoming[$1.id]?.count ?? 0)
            }.prefix(12))
        }
        func score(_ n: Note) -> Int? {
            let t = n.title.lowercased(), p = n.relPath.lowercased()
            if t.hasPrefix(q) { return 0 }
            if t.contains(q) { return 1 }
            if p.contains(q) { return 2 }
            var i = p.startIndex
            for ch in q {
                guard let f = p[i...].firstIndex(of: ch) else { return nil }
                i = p.index(after: f)
            }
            return 3
        }
        var scored: [(note: Note, score: Int)] = []
        for n in store.notes { if let sc = score(n) { scored.append((n, sc)) } }
        scored.sort { a, b in a.score != b.score ? a.score < b.score : a.note.relPath.count < b.note.relPath.count }
        return scored.prefix(30).map { $0.note }
    }

    var body: some View {
        let rs = results
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find or create a note…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { open(rs) }
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
                        ForEach(Array(rs.enumerated()), id: \.element.path) { i, n in
                            QuickOpenRow(note: n, selected: i == index)
                                .onTapGesture { index = i; open(rs) }
                                .id(i)
                        }
                        if !query.isEmpty && rs.isEmpty {
                            Text("Return creates “\(query)”").font(.callout).foregroundStyle(.secondary).padding(14)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: index) { _, i in proxy.scrollTo(i) }
            }
            .frame(height: 320)
        }
        .frame(width: 560)
        .onAppear { focused = true }
    }

    func open(_ rs: [Note]) {
        if rs.indices.contains(index) {
            store.openNote(rs[index])
        } else if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            store.createNote(named: query.trimmingCharacters(in: .whitespaces), near: store.opened?.note)
        }
        dismiss()
    }
}

struct QuickOpenRow: View {
    var note: Note
    var selected: Bool
    var body: some View {
        let fg: Color = selected ? .white : .primary
        let sub: Color = selected ? Color.white.opacity(0.8) : Color.secondary
        let bg: AnyShapeStyle = selected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.clear)
        HStack(spacing: 10) {
            Image(systemName: "doc.text").foregroundStyle(sub)
            VStack(alignment: .leading, spacing: 1) {
                Text(note.title).font(.callout.weight(.medium)).lineLimit(1).foregroundStyle(fg)
                Text(note.relPath).font(.caption).lineLimit(1).foregroundStyle(sub)
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(bg))
        .contentShape(Rectangle())
    }
}
