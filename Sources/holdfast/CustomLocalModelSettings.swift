import AppKit
import SwiftUI

struct CustomLocalModelRow: View {
    @EnvironmentObject var store: Store
    let model: CustomLocalModel
    var selected: () -> Void

    var body: some View {
        let ready = store.isDownloaded(model.id)
        VStack(alignment: .leading, spacing: 4) {
            ChoiceRow(selected: store.backend == .mlx && store.mlxRepo == model.id,
                      enabled: ready && store.canChangeLocalModel,
                      title: model.name, tag: "Custom", subtitle: subtitle,
                      action: { store.selectMLX(model.id); selected() }) {
                HStack(spacing: 8) {
                    if let fraction = store.downloads[model.id] {
                        ModelDownloadProgressView(progress: fraction)
                    } else if ready {
                        StatusBadge(status: .ready(MLXBackend.loadedRepo == model.id ? "Loaded" : "Files checked"))
                    } else if model.source == .huggingFace {
                        Button("Download") { store.downloadRepo(model.id) }
                            .controlSize(.small).disabled(!store.canChangeLocalModel)
                    } else {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            .help("Folder unavailable or incomplete. Add its new location if it moved.")
                    }
                    Menu {
                        if let folder = model.folder {
                            Button("Show in Finder") { NSWorkspace.shared.open(folder) }
                        }
                        Button("Remove from list") { store.removeLocalModel(model) }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .disabled(!store.canChangeLocalModel || store.downloads[model.id] != nil)
                        .help("Removing a model from this list keeps its files on disk.")
                }
            }
            if let error = store.downloadErrors[model.id] {
                Text(error).font(Theme.caption).foregroundStyle(.red).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
        }
    }

    private var subtitle: String {
        let source = model.source == .folder ? "Local folder" : model.location
        let missing = model.source == .folder && !store.isDownloaded(model.id) ? "Folder unavailable or incomplete. " : ""
        return "\(missing)\(source) · \(model.sizeDescription). Memory use will be higher. Not benchmarked with Holdfast."
    }
}

struct AddLocalModelView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var source = CustomLocalModel.Source.huggingFace
    @State private var repository = ""
    @State private var folder: URL?
    @State private var error: String?
    @State private var adding = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeader(title: "Add a local model", subtitle: "Use an MLX-compatible chat model on this Mac.")
            Picker("Source", selection: $source) {
                Text("Hugging Face").tag(CustomLocalModel.Source.huggingFace)
                Text("Local folder").tag(CustomLocalModel.Source.folder)
            }.pickerStyle(.segmented).disabled(adding)
                .onChange(of: source) { _, _ in error = nil }
            if source == .huggingFace {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Repository or model URL").font(Theme.callout)
                    TextField("owner/model or https://huggingface.co/owner/model", text: $repository)
                        .textFieldStyle(.roundedBorder).disabled(adding)
                        .onChange(of: repository) { _, _ in error = nil }
                    Text("We check the model's files and architecture first. Download its weights from the model list when you're ready. Access tokens and download sources are in Settings → Downloads.")
                        .font(Theme.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(folder?.lastPathComponent ?? "No folder selected").lineLimit(2)
                        Spacer()
                        Button("Choose folder…") { chooseFolder() }.disabled(adding)
                    }
                    if let folder { Text(folder.path).font(Theme.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    Text("Choose the folder containing config.json, tokenizer.json, and safetensors weights. Holdfast uses the files in place. Removing the model from the list keeps your files.")
                        .font(Theme.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Custom models may answer or use tools differently. File checks do not measure answer quality or tool support. All proposed note changes still wait in the Inbox.")
                .font(Theme.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error).font(Theme.callout).foregroundStyle(.red).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if adding { ProgressView().controlSize(.small); Text("Checking model…").font(Theme.caption) }
                Spacer()
                Button("Cancel") { task?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add model") { add() }.keyboardShortcut(.defaultAction)
                    .disabled(adding || !store.canChangeLocalModel || (source == .folder ? folder == nil : repository.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }
        .padding(24).frame(width: 560)
        .background(Theme.canvas)
        .onDisappear { task?.cancel() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose an MLX model folder"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { folder = panel.url; error = nil }
    }

    private func add() {
        adding = true; error = nil
        let repo = source == .huggingFace ? repository : nil
        let directory = source == .folder ? folder : nil
        task = Task {
            defer { adding = false }
            do {
                try await store.addLocalModel(repository: repo, folder: directory)
                try Task.checkCancellation()
                dismiss()
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}
