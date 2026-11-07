import AppKit
import SwiftUI

/// Settings window (⌘,): the answer model (MLX short list or Ollama), the
/// search reranker, the transcription model, and the vault.
struct SettingsView: View {
    var body: some View {
        TabView {
            AnswerSettings().tabItem { Label("Answer", systemImage: "sparkles") }
            SearchSettings().tabItem { Label("Search", systemImage: "magnifyingglass") }
            TranscriptionSettings().tabItem { Label("Transcription", systemImage: "waveform") }
            VaultSettings().tabItem { Label("Vault", systemImage: "folder") }
        }
        .frame(width: 580)
        .tint(Theme.accent)
    }
}

enum ModelStatus: Equatable {
    case checking, ready(String), missing(String)
}

// MARK: - Building blocks

struct SettingsHeader: View {
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.headline)
            Text(subtitle).font(Theme.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A selectable row with a radio mark; `trailing` holds status or a button.
struct ChoiceRow<Trailing: View>: View {
    var selected: Bool
    var enabled = true
    var title: String
    var tag: String?
    var subtitle: String
    var action: () -> Void
    @ViewBuilder var trailing: Trailing
    @State private var hover = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(Theme.title3)
                .foregroundStyle(selected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.secondary.opacity(enabled ? 0.5 : 0.25)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(Theme.callout.weight(.semibold))
                    if let tag { Pill(text: tag) }
                }
                Text(subtitle).font(Theme.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .opacity(enabled ? 1 : 0.6)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected ? Theme.accent.opacity(0.08) : (hover && enabled ? Color.primary.opacity(0.04) : .clear)))
        .contentShape(Rectangle())
        .onTapGesture { if enabled { action() } }
        .onHover { hover = $0 }
    }
}

struct GroupBox2<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 2) { content }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

struct StatusBadge: View {
    var status: ModelStatus
    var body: some View {
        switch status {
        case .checking: ProgressView().controlSize(.mini)
        case .ready(let s): Pill(text: s, icon: "checkmark", color: .green)
        case .missing(let s): Pill(text: s, icon: "exclamationmark.triangle", color: .orange)
        }
    }
}

// MARK: - Answer

struct AnswerSettings: View {
    @EnvironmentObject var store: Store
    @State private var ollamaStatus: ModelStatus = .checking
    @State private var tick = 0  // re-read load state after Unload

    let ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHeader(title: "Answer model",
                           subtitle: "Runs on this Mac with MLX and writes answers from the passages search finds. Takes effect on the next question.")
            GroupBox2 {
                ForEach(MLXModelSpec.shortList) { spec in mlxRow(spec) }
            }
            HStack(spacing: 6) {
                Image(systemName: "memorychip")
                Text(String(format: "This Mac has %.0f GB of memory. Models download from Hugging Face (mlx-community).", ramGB))
            }
            .font(Theme.caption).foregroundStyle(.secondary)

            SettingsHeader(title: "Other runtime", subtitle: "For comparison; needs the Ollama server running.")
            GroupBox2 {
                ChoiceRow(selected: store.backend == .ollama, title: "Qwen 3.8 27B", tag: "8-bit · Ollama",
                          subtitle: "~28 GB, ~5 tok/s. Measured 78% before the retrieval fixes.",
                          action: { store.backend = .ollama }) {
                    StatusBadge(status: ollamaStatus)
                }
            }
            let _ = tick
            if MLXBackend.isLoaded && store.backend == .ollama {
                HStack(spacing: 10) {
                    Image(systemName: "memorychip").foregroundStyle(.orange)
                    Text("\(MLXModelSpec.find(MLXBackend.loadedRepo ?? "")?.name ?? "The MLX model") is still in memory.").font(Theme.callout)
                    Spacer()
                    Button("Unload") { MLXBackend.unload(); tick += 1 }.disabled(store.busy != nil)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.1)))
            }
        }
        .padding(24)
        .task { ollamaStatus = await checkOllama() }
    }

    @ViewBuilder func mlxRow(_ spec: MLXModelSpec) -> some View {
        let downloaded = store.isDownloaded(spec.repo)
        let tooBig = spec.sizeGB > ramGB * 0.75
        ChoiceRow(selected: store.backend == .mlx && store.mlxRepo == spec.repo, enabled: downloaded,
                  title: spec.name, tag: "\(spec.detail) · \(String(format: "%.0f", spec.sizeGB)) GB",
                  subtitle: tooBig ? "Too large for this Mac's memory." : (store.downloadErrors[spec.repo].map { "Download failed: \($0)" } ?? spec.blurb),
                  action: { store.selectMLX(spec.repo) }) {
            if let f = store.downloads[spec.repo] {
                HStack(spacing: 6) {
                    ProgressView(value: f).frame(width: 70)
                    Text(String(format: "%.0f%%", f * 100)).font(Theme.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            } else if downloaded {
                StatusBadge(status: .ready(MLXBackend.loadedRepo == spec.repo ? "Loaded" : "Downloaded"))
            } else {
                Button("Download") { store.download(spec) }
                    .controlSize(.small)
                    .disabled(tooBig)
                    .help("Download \(String(format: "%.1f", spec.sizeGB)) GB from huggingface.co/\(spec.repo)")
            }
        }
    }

    func checkOllama() async -> ModelStatus {
        var req = URLRequest(url: Config.ollamaURL.appendingPathComponent("api/tags"))
        req.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = j["models"] as? [[String: Any]] else { return .missing("Not running") }
        let names = models.compactMap { $0["name"] as? String }
        return names.contains(where: { $0.hasPrefix(Config.llmModel) }) ? .ready("Installed") : .missing("Model not installed")
    }
}

// MARK: - Search

struct SearchSettings: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHeader(title: "Embedding model",
                           subtitle: "Finds passages by meaning, alongside keyword search. Changing it means re-indexing, so it's fixed for now.")
            GroupBox2 {
                ChoiceRow(selected: true, title: "Qwen3-Embedding 0.6B", tag: "MLX",
                          subtitle: "Multilingual, 1024 dimensions.", action: {}) {
                    if Config.embedModelDir != nil { StatusBadge(status: .ready("Ready")) }
                    else { DownloadButton(repo: Config.embedSpec.repo) { store.rebuildIndex(force: true) } }
                }
            }
            SettingsHeader(title: "Reranker",
                           subtitle: "Reads the 60 best candidates against the question and keeps only the relevant ones.")
            GroupBox2 {
                ChoiceRow(selected: store.rerankerOn, title: "Qwen3-Reranker 0.6B", tag: "4-bit · MLX",
                          subtitle: "Recommended. Lifted the eval from 79% to 98%, and declines questions the notes can't answer.",
                          action: { store.rerankerOn = true }) {
                    if Reranker.modelDir != nil { StatusBadge(status: .ready("Ready")) }
                    else { DownloadButton(repo: Reranker.repo) }
                }
                ChoiceRow(selected: !store.rerankerOn, title: "Off", tag: nil,
                          subtitle: "Keyword + meaning only. Faster, but weaker passages and no \"not in your notes\" answer.",
                          action: { store.rerankerOn = false }) { EmptyView() }
            }
        }
        .padding(24)
    }
}

// MARK: - Transcription

struct TranscriptionSettings: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHeader(title: "Transcription model",
                           subtitle: "Turns recordings and videos without captions into timestamped transcripts, on the Neural Engine. Applies to the next import.")
            GroupBox2 {
                ForEach(TranscriptionModel.allCases) { m in
                    let present = FileManager.default.fileExists(atPath: m.folder.path)
                    ChoiceRow(selected: store.transcription == m, title: m.name, tag: "0.6B · CoreML",
                              subtitle: m.blurb, action: { store.transcription = m }) {
                        StatusBadge(status: present ? .ready("Downloaded") : .missing("Downloads on first use"))
                    }
                }
            }
            Text("Measured here: Parakeet v3 transcribes at about 140× real time (an hour of audio in under 30 seconds).")
                .font(Theme.caption).foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

// MARK: - Vault

struct VaultSettings: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHeader(title: "Vault",
                           subtitle: "A folder of plain Markdown notes. It can be an Obsidian vault; the search index and question history live in its hidden .mackb folder.")
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").font(Theme.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.vault.lastPathComponent).font(Theme.callout.weight(.semibold))
                    Text(store.vault.path).font(Theme.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.vault]) }
                Button("Change…") { store.chooseVault() }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            Text(Config.inPlace
                 ? "Indexed in place: the app writes nothing into this folder. Its index, history, inbox and imports are in Application Support."
                 : "Managed by the app: imports are copied into sources/, approved memories into memory/.")
                .font(Theme.caption).foregroundStyle(.secondary)
            Picker("Profile", selection: $store.profile) {
                ForEach(Profile.all, id: \.id) { Text($0.name).tag($0) }
            }
            .help("Sets the answer prompt, the reranker's instruction and the suggested questions. Folders named like ministry or counseling always use the counseling profile.")
            HStack(spacing: 16) {
                Label("\(store.notes.count) notes", systemImage: "doc.on.doc")
                Label("\(store.indexCounts.chunks) passages", systemImage: "text.alignleft")
                Label("\(store.history.count) questions", systemImage: "clock.arrow.circlepath")
                Spacer()
                Button("Rebuild Index") { store.rebuildIndex() }.disabled(store.busy != nil)
            }
            .font(Theme.callout).foregroundStyle(.secondary)
        }
        .padding(24)
    }
}


/// "Download" for a search model, with progress; `then` runs when it finishes.
struct DownloadButton: View {
    @EnvironmentObject var store: Store
    var repo: String
    var then: (@MainActor () -> Void)? = nil
    var body: some View {
        if let f = store.downloads[repo] {
            ProgressView(value: f).frame(width: 80).help("Downloading \(repo)")
        } else {
            VStack(alignment: .trailing, spacing: 2) {
                Button("Download") { store.downloadRepo(repo, then: then) }.controlSize(.small)
                if let e = store.downloadErrors[repo] { Text(e).font(Theme.caption2).foregroundStyle(.red).lineLimit(2) }
            }
        }
    }
}
