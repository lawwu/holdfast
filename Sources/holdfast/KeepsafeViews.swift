import AppKit
import SwiftUI

/// Vault › Export Notes…: pick notes by a question and/or a folder, untick any, then save a checked ZIP.
/// Private notes are found but left unticked unless they're included on purpose.
struct ExportSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var query = ""
    @State private var folder = ""
    @State private var found: [Note] = []
    @State private var chosen: Set<URL> = []
    @State private var includePrivateNotes = false
    @State private var searching = false
    @State private var working = false
    @State private var result: String?

    var picked: [Note] { found.filter { chosen.contains($0.path) && (includePrivateNotes || !Profile.isPrivate($0.relPath)) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Export Notes").font(Theme.title2)
            Text("A ZIP of the chosen notes and the original documents they link to, with a checksum for every file, for a CPA, a doctor or whoever needs the records. It's checked after it's built.")
                .font(Theme.callout).foregroundStyle(.secondary)
            TextField("Title, e.g. 2025 taxes", text: $title).textFieldStyle(.roundedBorder)
            HStack {
                TextField("Find notes about… (e.g. 2025 taxes)", text: $query).textFieldStyle(.roundedBorder).onSubmit { find() }
                TextField("and/or a folder, e.g. finance/taxes", text: $folder).textFieldStyle(.roundedBorder).onSubmit { find() }
                Button(searching ? "Finding…" : "Find") { find() }.disabled(searching || (query.isEmpty && folder.isEmpty))
            }
            if !found.isEmpty {
                List(found, id: \.path) { n in
                    let isPrivate = Profile.isPrivate(n.relPath)
                    Toggle(isOn: Binding(get: { chosen.contains(n.path) && (includePrivateNotes || !isPrivate) },
                                         set: { if $0 { chosen.insert(n.path) } else { chosen.remove(n.path) } })) {
                        HStack {
                            Text(n.title).lineLimit(1)
                            if isPrivate { Pill(text: "private", icon: "lock.fill", color: .orange) }
                            Spacer()
                            Text(n.relPath).font(Theme.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .disabled(isPrivate && !includePrivateNotes)
                }
                .frame(minHeight: 220)
                Toggle("Include private notes (left out unless ticked here)", isOn: $includePrivateNotes)
            }
            if let result { Text(result).font(Theme.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack {
                Text(found.isEmpty ? "" : "\(picked.count) of \(found.count) notes").font(Theme.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { dismiss() }
                Button(working ? "Exporting…" : "Export ZIP…") { export() }
                    .buttonStyle(.borderedProminent).disabled(picked.isEmpty || working)
            }
        }
        .padding(22)
        .frame(width: 720)
    }

    func find() {
        searching = true
        Task {
            let ns = await store.exportCandidates(query: query, folder: folder)
            found = ns
            chosen = Set(ns.map(\.path))
            searching = false
            if title.isEmpty { title = query.isEmpty ? folder : query }
        }
    }

    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = (title.isEmpty ? "Holdfast export" : title) + ".zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        working = true
        let notes = picked, name = title, isPrivate = includePrivateNotes
        Task.detached {
            let text: String
            do {
                let r = try Export.build(notes, includePrivateNotes: isPrivate, title: name, to: url)
                text = "Exported \(r.notes) notes and \(r.originals) originals to \(url.lastPathComponent)"
                    + (r.verified ? "; every file checked against its checksum." : "; the check found differences, so don't rely on this copy.")
            } catch {
                text = "Export failed: \(error)"
            }
            await MainActor.run {
                result = text
                working = false
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }
}
