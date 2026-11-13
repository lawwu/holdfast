import SwiftUI
import ModelProviders
import HuggingFace

struct ModelsView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var downloads = ModelDownloads.shared
    @ObservedObject private var audio = AudioModels.shared
    @State private var tab = "Recommended"
    @State private var query = ""
    @State private var adding = false
    @State private var settings: ProfileSelection?
    @State private var deleting: String?
    @State private var results: [String] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var message: String?
    @State private var inspecting: String?

    init(tab: String = "Recommended") { _tab = State(initialValue: tab) }

    private var models: [MLXModelSpec] {
        let all = tab == "Recommended" ? MLXModelSpec.shortList : MLXModelSpec.available.filter { store.isDownloaded($0.repo) }
        return all.filter { query.isEmpty || "\($0.name) \($0.repo)".localizedCaseInsensitiveContains(query) }
    }
    private var families: [String] { models.reduce(into: []) { names, model in
        let name = ModelIdentity.family(model.repo); if !names.contains(name) { names.append(name) }
    } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Models").font(Theme.title2)
                    Text("Choose what runs on your Mac.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Settings for current model…") {
                    let c = store.backend.serverKind.map(ProviderSettings.current)
                    settings = ProfileSelection(model: c?.model ?? store.mlxRepo, endpoint: c?.baseURL)
                }.disabled(!store.canChangeLocalModel)
                Button("Add model…") { adding = true }.disabled(!store.canChangeLocalModel)
            }
            Picker("Show", selection: $tab) {
                ForEach(["Recommended", "Downloaded", "Browse", "Downloads"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented)
            if tab != "Downloads" {
                HStack {
                    TextField(tab == "Browse" ? "Search model names, e.g. Qwen or Gemma" : "Filter models", text: $query)
                        .textFieldStyle(.roundedBorder).onSubmit { if tab == "Browse" { browse() } }
                    if tab == "Browse" { Button("Search") { browse() }.disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
            }
            if let message { Text(message).font(Theme.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if tab == "Downloads" { downloadList }
                    else if tab == "Browse" { browseList }
                    else {
                        if tab == "Recommended" {
                            Text("4-bit usually offers the best balance. Higher precision needs more memory; it does not always improve answers.")
                                .font(Theme.callout).foregroundStyle(.secondary)
                        }
                        ForEach(families, id: \.self) { family in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(family).font(Theme.headline)
                                ForEach(models.filter { ModelIdentity.family($0.repo) == family }) { spec in
                                    ModelHubRow(spec: spec, settings: { settings = ProfileSelection(model: spec.repo) }, deleting: { deleting = spec.repo })
                                }
                            }.card(padding: 14)
                        }
                        if tab == "Downloaded" { supportingModels }
                        if families.isEmpty { Text("No matching answer models. Browse or add a model to get started.").foregroundStyle(.secondary) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text(String(format: "%.0f GB memory · Downloads use Settings → Downloads", Recommend.thisMacGB))
                Spacer()
                if MLXBackend.isLoaded {
                    Button("Free answer model memory") { MLXBackend.unload(); store.objectWillChange.send() }
                        .disabled(!store.canChangeLocalModel)
                        .help("Keeps downloaded files. The model reloads next time you ask.")
                }
            }.font(Theme.caption).foregroundStyle(.secondary)
            Text("LocalMLX runs on this Mac. Server providers use the address chosen in Settings. Vault changes always need Inbox approval.")
                .font(Theme.caption).foregroundStyle(.secondary)
        }
        .padding(22).background(Theme.canvas)
        .frame(minWidth: 720, idealWidth: 800, minHeight: 560, idealHeight: 680)
        .onAppear { store.refreshLocalModels(); audio.refresh() }
        .onDisappear { searchTask?.cancel() }
        .onChange(of: tab) { _, _ in query = ""; message = nil; searchTask?.cancel(); searching = false }
        .sheet(isPresented: $adding) { AddLocalModelView().environmentObject(store) }
        .sheet(item: $settings) { ModelProfileEditor(selection: $0).environmentObject(store) }
        .confirmationDialog("Delete this model's downloaded files?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete download", role: .destructive) {
                guard let id = deleting else { return }
                do { try store.deleteModelDownload(id) }
                catch { message = error.localizedDescription }
                deleting = nil
            }
        } message: { Text("Your notes and settings are kept. Shared caches and folders you added are managed in Finder.") }
    }

    @ViewBuilder private var downloadList: some View {
        if downloads.items.isEmpty { Text("No downloads yet. Choose a model in Recommended or Browse.").foregroundStyle(.secondary) }
        ForEach(downloads.items) { item in
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name).font(Theme.headline)
                    Text(item.state.rawValue).font(Theme.caption).foregroundStyle(.secondary)
                    if let error = item.error { Text(error).font(Theme.caption).foregroundStyle(.red).textSelection(.enabled) }
                }
                Spacer()
                if item.state == .downloading {
                    ModelDownloadProgressView(progress: item.progress)
                    Button("Pause") { downloads.pause(item.id) }
                } else if item.state == .queued {
                    Button("Cancel") { downloads.pause(item.id) }
                } else if item.state == .paused || item.state == .failed {
                    Button(item.state == .failed ? "Retry" : "Resume") { downloads.resume(item.id) }
                    Button("Dismiss") { downloads.forget(item.id) }
                } else { Button("Dismiss") { downloads.forget(item.id) } }
                if ![.queued, .downloading].contains(item.state) {
                    Button("Delete files…") { deleting = item.id }.disabled(!store.canChangeLocalModel)
                }
            }.card(padding: 14)
        }
        Text("Downloads run one at a time. Pausing keeps partial files; Resume reuses them when the source supports byte ranges. Interrupted downloads can be resumed after restarting Holdfast. Dismiss keeps files; Delete files removes that download.")
            .font(Theme.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var browseList: some View {
        Text("Search Hugging Face or your configured mirror for MLX models. This sends the search words, never your notes. Compatibility is checked before a model is added.")
            .font(Theme.callout).foregroundStyle(.secondary)
        if searching { ProgressView("Finding models…") }
        ForEach(results, id: \.self) { repo in
            HStack {
                VStack(alignment: .leading) {
                    Text(ModelIdentity.family(repo)).font(Theme.headline)
                    Text(repo).font(Theme.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text("\(ModelIdentity.precision(repo) ?? "Precision varies") · Not tested in Holdfast").font(Theme.caption)
                }
                Spacer()
                if MLXModelSpec.available.contains(where: { $0.repo == repo }) { Text("Added").foregroundStyle(.secondary) }
                else {
                    Button(inspecting == repo ? "Checking…" : "Add") {
                        inspecting = repo
                        Task {
                            defer { inspecting = nil }
                            do { try await store.addLocalModel(repository: repo, folder: nil); message = "Added. Download it from Your added models below." }
                            catch { message = error.localizedDescription }
                        }
                    }.disabled(inspecting != nil || !store.canChangeLocalModel)
                }
            }.card(padding: 14)
        }
        if !store.customLocalModels.isEmpty {
            Text("Your added models").font(Theme.headline)
            ForEach(store.customLocalModels) { model in
                ModelHubRow(spec: model.spec, settings: { settings = ProfileSelection(model: model.id) }, deleting: { deleting = model.id })
                    .card(padding: 14)
            }
        }
    }

    @ViewBuilder private var supportingModels: some View {
        Text("Search and speech").font(Theme.headline)
        ForEach([Config.embedSpec.repo], id: \.self) { repo in
            if store.isDownloaded(repo) {
                ModelHubRow(spec: .init(repo: repo, name: repo.split(separator: "/").last.map(String.init) ?? repo,
                    detail: "Search model", sizeGB: 0, blurb: "Managed in Settings → Search"),
                    settings: nil, deleting: { deleting = repo }).card(padding: 14)
            }
        }
        ForEach(RerankerModel.allCases) { model in
            RerankerModelRow(model: model, delete: { deleting = model.id })
        }
        ForEach(TranscriptionModel.allCases) { model in
            HStack {
                VStack(alignment: .leading) {
                    Text(model.name).font(Theme.headline)
                    Text(model.blurb).font(Theme.caption).foregroundStyle(.secondary)
                    if audio.available.contains(model.id) { ModelDiskLabel(directory: model.folder) }
                }
                Spacer()
                if audio.available.contains(model.id) {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(audio.preparing.contains(model.id) ? "Preparing on this Mac…" : "Ready · prepares on first use").font(Theme.caption).foregroundStyle(.secondary)
                        Button("Delete download…") { deleting = "audio:" + model.id }.disabled(!store.canChangeLocalModel)
                    }
                }
                else if let item = downloads.item("audio:" + model.id), [.downloading, .queued].contains(item.state) { Text(item.state.rawValue).font(Theme.caption) }
                else { Button("Download") { audio.start(model) } }
            }.card(padding: 14)
        }
    }

    private func browse() {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return }
        searchTask?.cancel(); searching = true; message = nil
        searchTask = Task {
            do {
                let source = try ModelDownloadSource.current()
                var url = URLComponents(url: URL(string: source.endpoint)!.appendingPathComponent("api/models"), resolvingAgainstBaseURL: false)!
                url.queryItems = [.init(name: "search", value: search), .init(name: "filter", value: "mlx"),
                                  .init(name: "sort", value: "downloads"), .init(name: "direction", value: "-1"), .init(name: "limit", value: "30")]
                var request = URLRequest(url: url.url!); request.timeoutInterval = 30
                let provider: TokenProvider = source.token.map { $0.isEmpty ? .none : .fixed(token: $0) } ?? .environment
                if let token = try await provider.getToken() { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw HoldfastError("This source could not search models. You can still add a repository ID or local folder.") }
                struct Hit: Decodable { let id: String }
                let hits = try JSONDecoder().decode([Hit].self, from: data)
                try Task.checkCancellation()
                results = Array(Set(hits.map(\.id))).sorted()
                message = results.isEmpty ? "No MLX models found. Try a shorter name or Add model…." : nil
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
            if !Task.isCancelled { searching = false }
        }
    }
}

private struct ModelHubRow: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var downloads = ModelDownloads.shared
    let spec: MLXModelSpec
    let settings: (() -> Void)?
    let deleting: (() -> Void)?
    private var measured: ModelScore? { ModelCatalog.entries.first { $0.repo == spec.repo } }
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(spec.detail == "Custom" ? (ModelIdentity.precision(spec.repo) ?? spec.name) : spec.detail).font(Theme.headline)
                    if measured != nil { Text("Tested").font(Theme.caption).foregroundStyle(.secondary).help("Evaluated on " + ModelCatalog.measuredOn) }
                    if store.mlxRepo == spec.repo && store.backend == .mlx { Text("Selected").font(Theme.caption).foregroundStyle(Theme.accent) }
                }
                Text(spec.repo).font(Theme.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if spec.sizeGB > 0 {
                    Text(String(format: "%.1f GB download · %@ %.0f GB memory", spec.sizeGB,
                        measured == nil ? "allow about" : "measured peak", measured?.peakGB ?? (spec.sizeGB * 1.25 + 3)))
                        .font(Theme.caption).foregroundStyle(.secondary)
                }
                if measured == nil && settings != nil { Text("Not tested in Holdfast. Memory varies with context length.").font(Theme.caption).foregroundStyle(.secondary) }
                if let directory = MLXBackend.modelDir(repo: spec.repo) { ModelDiskLabel(directory: directory) }
                if let error = store.downloadErrors[spec.repo] { Text(error).font(Theme.caption).foregroundStyle(.red) }
                if settings != nil { Text(spec.blurb).font(Theme.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 8) {
                if let item = downloads.item(spec.repo), [.queued, .downloading].contains(item.state) {
                    if item.state == .downloading { ModelDownloadProgressView(progress: item.progress) }
                    else { Text("Queued").font(Theme.caption) }
                    Button("Cancel / Pause") { downloads.pause(spec.repo) }
                } else if store.isDownloaded(spec.repo) {
                    Text(MLXBackend.loadedRepo == spec.repo ? "Loaded in memory" : store.busy?.hasPrefix("Loading") == true && store.mlxRepo == spec.repo ? "Loading into memory…" : "Ready").font(Theme.caption).foregroundStyle(.green)
                    if settings != nil {
                        Button("Use for Ask") { store.selectMLX(spec.repo) }.disabled(!store.canChangeLocalModel)
                    }
                    if let deleting, ModelStorage.ownedDirectory(spec.repo).map({ FileManager.default.fileExists(atPath: $0.path) }) == true {
                        Button("Delete download…", action: deleting).disabled(!store.canChangeLocalModel)
                    } else if let directory = MLXBackend.modelDir(repo: spec.repo) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([directory]) }
                    }
                } else {
                    Button(downloads.item(spec.repo)?.state == .paused ? "Resume" : "Download") { store.download(spec) }
                        .disabled(spec.sizeGB > Recommend.thisMacGB * 0.75)
                }
                if let settings { Button("Settings…", action: settings).disabled(!store.canChangeLocalModel) }
                if let custom = CustomLocalModels.find(spec.repo) {
                    Button("Remove from list") { store.removeLocalModel(custom) }
                        .disabled(!store.canChangeLocalModel || [.queued, .downloading].contains(downloads.item(spec.repo)?.state ?? .ready))
                }
            }.controlSize(.small)
        }
    }
}

struct ModelDiskLabel: View {
    let directory: URL
    @State private var bytes: Int64?
    var body: some View {
        Text(bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) + " on disk" } ?? "Measuring disk use…")
            .font(Theme.caption).foregroundStyle(.secondary)
            .task(id: directory) { bytes = await Task.detached { ModelStorage.bytes(at: directory) }.value }
    }
}

struct ProfileSelection: Identifiable {
    var model: String
    var endpoint: String? = nil
    var id: String { ModelPreferences.key(model, endpoint: endpoint) }
}

struct ModelProfileEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let selection: ProfileSelection
    @State private var profile = ModelProfile()
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Model settings").font(Theme.title2)
            Text(selection.model).font(Theme.callout).textSelection(.enabled)
            Text("Saved for this model. Defaults favor everyday note work. Larger context limits use more memory; the model and server must support the limit you choose.")
                .font(Theme.callout).foregroundStyle(.secondary)
            Form {
                Picker("Context limit", selection: $profile.contextTokens) {
                    ForEach([16384, 32768, 65536, 131072], id: \.self) { Text("\($0) tokens").tag($0) }
                }
                TextField("Maximum answer tokens", value: $profile.maxOutputTokens, format: .number)
                Toggle("Thinking (when supported)", isOn: $profile.thinking)
                DisclosureGroup("Advanced sampling") {
                    TextField("Temperature", value: $profile.temperature, format: .number)
                    TextField("Top P", value: $profile.topP, format: .number)
                    TextField("Top K", value: $profile.topK, format: .number)
                    TextField("Presence penalty", value: $profile.presencePenalty, format: .number)
                    Text("Some servers ignore unsupported sampling controls.").font(Theme.caption).foregroundStyle(.secondary)
                }
            }
            if let error { Text(error).font(Theme.caption).foregroundStyle(.red) }
            HStack {
                Button("Restore defaults") { profile = .automatic(for: selection.model) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try ModelPreferences.save(profile, model: selection.model, endpoint: selection.endpoint)
                        store.objectWillChange.send(); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(!store.canChangeLocalModel)
            }
        }.padding(24).frame(width: 500)
        .onAppear { profile = ModelPreferences.load(selection.model, endpoint: selection.endpoint) }
    }
}
