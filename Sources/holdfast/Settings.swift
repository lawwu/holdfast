import AppKit
import SwiftUI
import ModelProviders

/// Settings window (⌘,): the answer model (MLX short list or Ollama), the
/// search reranker, the transcription model, and the vault.
struct SettingsView: View {
    var body: some View {
        TabView {
            ScrollView { AnswerSettings() }.tabItem { Label("Answer", systemImage: "sparkles") }
            ScrollView { SearchSettings() }.tabItem { Label("Search", systemImage: "magnifyingglass") }
            ScrollView { TranscriptionSettings() }.tabItem { Label("Transcription", systemImage: "waveform") }
            ScrollView { VaultSettings() }.tabItem { Label("Vault", systemImage: "folder") }
        }
        .frame(width: 600, height: 520)
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
    @State private var tick = 0  // re-read load state after Unload
    @State private var choosingModel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsHeader(title: "Answer model",
                           subtitle: "Choose where answers run. Applies to your next question.")
            Picker("Provider", selection: $store.backend) {
                Text("LocalMLX · Built in").tag(Backend.mlx)
                Text("Ollama").tag(Backend.ollama)
                Text("LM Studio").tag(Backend.lmStudio)
                Text("Custom server").tag(Backend.remote)
            }.pickerStyle(.segmented).disabled(store.busy != nil || store.asking)
            if let kind = store.backend.serverKind {
                ServerConnectionSettings(kind: kind).id(kind)
            } else {
                localModel
            }
            let pending = PiAgent.pending
            if !pending.isEmpty {
                DisclosureGroup("Interrupted conversations (\(pending.count))") {
                    ForEach(pending) { request in
                        Button {
                            store.newQuestion()
                            store.pane = .ask
                            store.conversationId = request.conversationID
                            store.question = "What was completed before the interruption?"
                            // Open a draft. Never resubmit the interrupted job automatically.
                        } label: {
                            Text(request.question).lineLimit(2).multilineTextAlignment(.leading)
                        }.disabled(store.busy != nil || store.asking)
                    }
                }
            }
            let _ = tick
            if MLXBackend.isLoaded && store.backend != .mlx {
                HStack(spacing: 10) {
                    Image(systemName: "memorychip").foregroundStyle(.orange)
                    Text("\(MLXModelSpec.find(MLXBackend.loadedRepo ?? "")?.name ?? "The MLX model") is still in memory.").font(Theme.callout)
                    Spacer()
                    Button("Unload") { MLXBackend.unload(); tick += 1 }.disabled(store.busy != nil || store.asking)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.1)))
            }
            Label("Changes to notes wait for your approval in the Inbox.", systemImage: "checkmark.shield")
                .font(Theme.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .sheet(isPresented: $choosingModel) { LocalModelBrowser().environmentObject(store) }
    }

    private var localModel: some View {
        VStack(alignment: .leading, spacing: 12) {
            let spec = MLXModelSpec.find(store.mlxRepo)
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(spec?.name ?? store.mlxRepo.components(separatedBy: "/").last ?? store.mlxRepo)
                        .font(Theme.headline).textSelection(.enabled)
                    if let spec {
                        Text("\(spec.detail) · \(String(format: "%.1f", spec.sizeGB)) GB download")
                            .font(Theme.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button("Change model…") { choosingModel = true }
                    .disabled(store.busy != nil || store.asking)
            }
            HStack {
                if store.isDownloaded(store.mlxRepo) {
                    StatusBadge(status: .ready(MLXBackend.loadedRepo == store.mlxRepo ? "Loaded" : "Ready"))
                } else {
                    DownloadButton(repo: store.mlxRepo)
                        .disabled(store.busy != nil || store.asking || spec.map { localModelFit($0) == .no } == true)
                }
                Spacer()
                Label("Runs on this Mac", systemImage: "lock.fill")
                    .font(Theme.caption).foregroundStyle(.secondary)
            }
        }.card(padding: 16)
    }
}

/// The full catalogue stays in a bounded sheet, separate from the selected model.
struct LocalModelBrowser: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var models: [MLXModelSpec] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return MLXModelSpec.shortList.filter {
            search.isEmpty || "\($0.name) \($0.detail) \($0.repo)".localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Choose a local model").font(Theme.title2)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("Search models", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if query.isEmpty {
                        DisclosureGroup("Help me choose") {
                            RecommendationRows().padding(.top, 8)
                                .disabled(store.busy != nil || store.asking)
                        }.font(Theme.callout)
                    }
                    if models.isEmpty {
                        Text("No matching models.").foregroundStyle(.secondary).padding(.vertical)
                    } else {
                        GroupBox2 { ForEach(models) { spec in mlxRow(spec) } }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(String(format: "This Mac has %.0f GB of memory. Models download from Hugging Face.", Recommend.thisMacGB))
                .font(Theme.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 640, height: 540)
        .background(Theme.canvas)
    }

    @ViewBuilder func mlxRow(_ spec: MLXModelSpec) -> some View {
        let downloaded = store.isDownloaded(spec.repo)
        let fit = localModelFit(spec)
        let tooBig = fit == .no
        ChoiceRow(selected: store.backend == .mlx && store.mlxRepo == spec.repo, enabled: downloaded && store.busy == nil && !store.asking,
                  title: spec.name, tag: "\(spec.detail) · \(String(format: "%.0f", spec.sizeGB)) GB",
                  subtitle: tooBig ? "Too large for this Mac's memory. " + spec.blurb
                      : (store.downloadErrors[spec.repo].map { "Download failed: \($0)" } ?? (fit == .tight ? "Tight on this Mac's memory. " : "") + spec.blurb),
                  action: { store.selectMLX(spec.repo); dismiss() }) {
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
                    .disabled(tooBig || store.busy != nil || store.asking)
                    .help("Download \(String(format: "%.1f", spec.sizeGB)) GB from huggingface.co/\(spec.repo)")
            }
        }
    }
}

private func localModelFit(_ spec: MLXModelSpec) -> Recommend.Fit {
    let measured = ModelCatalog.entries.first { $0.repo == spec.repo }
    return measured.map { Recommend.fit($0, ramGB: Recommend.thisMacGB) }
        ?? (spec.sizeGB > Recommend.thisMacGB * 0.75 ? .no : .unknown)
}

// MARK: - Search

struct SearchSettings: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Search by meaning", isOn: Binding(
                    get: { store.searchByMeaning && ProcessInfo.processInfo.environment["HOLDFAST_EMBED"] != "none" },
                    set: { store.setSearchByMeaning($0) }))
                    .toggleStyle(.switch).font(Theme.headline)
                    .disabled(!store.canChangeMeaningSearch)
                Text("Find related ideas even when the wording is different. Keyword search always stays on.")
                    .font(Theme.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if ProcessInfo.processInfo.environment["HOLDFAST_EMBED"] == "none" {
                    Text("Meaning search is disabled for this launch by HOLDFAST_EMBED=none.")
                        .font(Theme.caption).foregroundStyle(.secondary)
                } else if store.searchByMeaning {
                    HStack {
                        Text("\(Config.embedSpec.label) · on this Mac").font(Theme.caption)
                        Spacer()
                        if Config.embedModelDir == nil {
                            DownloadButton(repo: Config.embedSpec.repo) { store.prepareMeaningSearch() }
                                .disabled(!store.canChangeMeaningSearch)
                        } else if store.preparingMeaningSearch {
                            ProgressView().controlSize(.small)
                            Text("Preparing…").font(Theme.caption)
                        } else if store.indexCounts.chunks > store.indexCounts.vectors
                                    || (!store.notes.isEmpty && store.indexCounts.chunks == 0)
                                    || store.meaningSearchError != nil {
                            Button("Prepare missing passages") { store.prepareMeaningSearch() }
                                .controlSize(.small).disabled(!store.canChangeMeaningSearch)
                        } else {
                            StatusBadge(status: .ready("Ready"))
                        }
                    }
                    if let error = store.meaningSearchError {
                        Text(error).font(Theme.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Using keyword search. The saved index and model download are kept.")
                        .font(Theme.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 14)
            SettingsHeader(title: "Reranker",
                           subtitle: "Improves search results, with or without meaning search.")
            GroupBox2 {
                ChoiceRow(selected: store.rerankerOn, title: "Qwen3-Reranker 0.6B", tag: "4-bit · MLX",
                          subtitle: "Recommended. Reads candidate passages and keeps the most relevant ones.",
                          action: { store.rerankerOn = true }) {
                    if Reranker.modelDir != nil { StatusBadge(status: .ready("Ready")) }
                    else { DownloadButton(repo: Reranker.repo) }
                }
                ChoiceRow(selected: !store.rerankerOn, title: "Off", tag: nil,
                          subtitle: "Uses the initial search ranking. Faster, but less precise.",
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
                           subtitle: "A folder of plain Markdown notes. It can be an Obsidian vault; the search index and question history live in its hidden .holdfast folder.")
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

            SettingsHeader(title: "Backups",
                           subtitle: "A dated copy of this vault and Holdfast's records for it (versions, filings, history, originals), with a checksum for every file. Keep it on another drive.")
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.fill").font(Theme.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Backup.folder?.path ?? "No backup folder yet").font(Theme.callout).lineLimit(1).truncationMode(.middle)
                    Text((UserDefaults.standard.object(forKey: "lastBackup:" + store.vault.path) as? Date)
                            .map { "Last backup " + $0.formatted(.relative(presentation: .named)) } ?? "Never backed up")
                        .font(Theme.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose…") { _ = store.chooseBackupFolder() }
            }
            HStack {
                Button("Back Up Now") { store.backupNow() }.buttonStyle(.borderedProminent).disabled(store.importProgress != nil)
                Button("Verify") { store.checkLatestBackup(restore: false) }.help("Re-read every file of the newest backup and compare it with its checksum")
                Button("Test Restore") { store.checkLatestBackup(restore: true) }.help("Restore the newest backup into a temporary folder, check it and open every note, then remove it")
            }
            if let s = store.backupStatus { Text(s).font(Theme.caption).foregroundStyle(.secondary).textSelection(.enabled) }
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
