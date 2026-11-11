import SwiftUI

struct RerankerSettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.openWindow) private var openWindow
    private var model: RerankerModel? { RerankerModel(rawValue: Reranker.repo) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Rerank search results", isOn: Binding(
                get: { store.rerankerOn && !RerankerPreferences.disabledForLaunch },
                set: { store.setRerankerEnabled($0) }))
                .toggleStyle(.switch)
                .disabled(!store.canChangeReranker || RerankerPreferences.disabledForLaunch)
            Picker("Model", selection: Binding(get: { store.rerankerModel }, set: { store.selectReranker($0) })) {
                ForEach(RerankerModel.allCases) { Text($0.menuLabel).tag($0) }
            }.disabled(!store.canChangeReranker || RerankerPreferences.hasModelOverride)
            if RerankerPreferences.hasModelOverride {
                Text("A launch override selects the reranker: \(Reranker.repo). Your saved choice applies when the override is removed.")
                    .font(Theme.caption).foregroundStyle(.secondary).textSelection(.enabled)
            } else if let model {
                Text(model.detail).font(Theme.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("\(model.precision) · \(model.sizeLabel) · allow about \(Int(model.memoryGB)) GB memory")
                    .font(Theme.caption).foregroundStyle(.secondary)
            }
            HStack {
                RerankerDownloadControls(repo: Reranker.repo)
                Spacer()
                Button("Manage downloads…") { openWindow(id: "models") }.controlSize(.small)
            }
            if RerankerPreferences.disabledForLaunch {
                Text("Reranking is disabled for this launch by HOLDFAST_RERANK=0.")
                    .font(Theme.caption).foregroundStyle(.secondary)
            } else if !store.rerankerOn {
                Text("Off. Search keeps its original result order. Your model choice and downloads are kept.")
                    .font(Theme.caption).foregroundStyle(.secondary)
            } else if let error = Reranker.loadError {
                Text("Could not load this reranker: \(error). Search is using its original result order.")
                    .font(Theme.caption).foregroundStyle(.red).textSelection(.enabled)
                Button("Retry on next search") { store.retryReranker() }.controlSize(.small).disabled(!store.canChangeReranker)
            } else if !RerankerDownloadControls.isAvailable(Reranker.repo) {
                Text("Download this model to use it. Until it is ready, search keeps its original result order.")
                    .font(Theme.caption).foregroundStyle(.secondary)
            }
            Text("Runs on this Mac, with keyword or meaning search. Changing rerankers does not rebuild your index. Memory is shared with the answer and embedding models.")
                .font(Theme.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.card(padding: 14)
    }
}

struct RerankerDownloadControls: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var downloads = ModelDownloads.shared
    let repo: String

    static func isAvailable(_ repo: String) -> Bool {
        guard let directory = Reranker.directory(for: repo) else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path)
    }
    var body: some View {
        Group {
            if let item = downloads.item(repo), item.state == .queued || item.state == .downloading {
                if item.state == .queued { Text("Queued").font(Theme.caption).foregroundStyle(.secondary) }
                else { ModelDownloadProgressView(progress: item.progress) }
                Button(item.state == .queued ? "Cancel" : "Pause") { downloads.pause(repo) }
            } else if Self.isAvailable(repo) {
                StatusBadge(status: .ready(Reranker.loadedRepo == repo ? "Loaded" : "Ready"))
                if Reranker.loadedRepo == repo {
                    Button("Free memory") { store.retryReranker() }
                        .disabled(!store.canChangeReranker).help("Keeps model files. Reloads on the next search if reranking is on.")
                }
            } else if repo == Reranker.repo, RerankerPreferences.override(ProcessInfo.processInfo.environment["HOLDFAST_RERANK_DIR"]) != nil {
                Text("The model folder set for this launch is missing its files.").font(Theme.caption).foregroundStyle(.orange)
            } else {
                Button(downloads.item(repo)?.state == .paused ? "Resume" : downloads.item(repo)?.state == .failed ? "Retry download" : "Download") { store.downloadRepo(repo) }
            }
        }.controlSize(.small)
    }
}

struct RerankerModelRow: View {
    @EnvironmentObject var store: Store
    let model: RerankerModel
    let delete: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(model.name).font(Theme.headline)
                    if store.rerankerOn && Reranker.repo == model.id { Text("Selected").font(Theme.caption).foregroundStyle(Theme.accent) }
                }
                Text("\(model.precision) · \(model.sizeLabel)").font(Theme.caption).foregroundStyle(.secondary)
                Text(model.detail).font(Theme.caption).foregroundStyle(.secondary)
                if let directory = Reranker.directory(for: model.id) { ModelDiskLabel(directory: directory) }
                if let error = store.downloadErrors[model.id] { Text(error).font(Theme.caption).foregroundStyle(.red) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 8) {
                RerankerDownloadControls(repo: model.id)
                if RerankerDownloadControls.isAvailable(model.id) {
                    Button("Use reranker") { store.selectReranker(model); store.setRerankerEnabled(true) }
                        .disabled(!store.canChangeReranker || RerankerPreferences.hasModelOverride || RerankerPreferences.disabledForLaunch)
                    if ModelStorage.ownedDirectory(model.id).map({ FileManager.default.fileExists(atPath: $0.path) }) == true {
                        Button("Delete download…", action: delete).disabled(!store.canChangeLocalModel)
                    } else if let directory = Reranker.directory(for: model.id) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([directory]) }
                    }
                }
            }.controlSize(.small)
        }.card(padding: 14)
    }
}
