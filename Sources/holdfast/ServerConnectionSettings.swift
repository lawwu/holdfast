import SwiftUI
import ModelProviders

struct ServerConnectionSettings: View {
    @EnvironmentObject var store: Store
    let kind: ServerKind
    @State private var address = ""
    @State private var model = ""
    @State private var contextWindow = 32768
    @State private var key = ""
    @State private var models: [String] = []
    @State private var status: String?
    @State private var checking = false

    init(kind: ServerKind) {
        self.kind = kind
        let c = ProviderSettings.saved(kind)
        _address = State(initialValue: c.baseURL)
        _model = State(initialValue: c.model)
        _contextWindow = State(initialValue: c.contextWindow)
    }

    private var configuration: ServerConfiguration {
        .init(kind: kind, baseURL: address.trimmingCharacters(in: .whitespacesAndNewlines),
              model: model.trimmingCharacters(in: .whitespacesAndNewlines), contextWindow: contextWindow)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind == .ollama ? "Connect to Ollama’s native API." : "Connect to an OpenAI-compatible chat-completions API.")
                .font(Theme.callout)
            TextField("API base address", text: $address).textFieldStyle(.roundedBorder)
                .onChange(of: address) { _, _ in key = ""; models = []; status = nil }
            Text(kind == .ollama ? "For example, http://localhost:11434" : "For example, http://localhost:1234/v1. Include any proxy prefix in the API base.")
                .font(Theme.caption).foregroundStyle(.secondary)
            SecureField("API key (optional, saved in Keychain)", text: $key).textFieldStyle(.roundedBorder)
            HStack {
                TextField("Model ID", text: $model).textFieldStyle(.roundedBorder)
                if !models.isEmpty {
                    Menu("Choose model") { ForEach(models, id: \.self) { value in Button(value) { model = value } } }
                }
                Button(checking ? "Checking…" : "Discover Models") { Task { await discover() } }
                    .disabled(checking || address.isEmpty)
            }
            HStack {
                Text("Context window").font(Theme.callout)
                TextField("Tokens", value: $contextWindow, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder).frame(width: 100)
                Text("Match your loaded server model (at least 16384).").font(Theme.caption).foregroundStyle(.secondary)
            }
            Text("Choose a model with tool support for research and edits. Questions and note excerpts go to this server; its configuration controls where inference runs. Counseling content uses LocalMLX. Changes still wait in the Inbox.")
                .font(Theme.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let status { Text(status).font(Theme.callout).textSelection(.enabled) }
            HStack {
                Button("Save Connection") {
                    do {
                        try ProviderSettings.save(configuration, key: key)
                        store.objectWillChange.send()
                        status = "Saved. This connection will be used for your next question."
                    } catch { status = error.localizedDescription }
                }.disabled(model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checking)
            }
        }
        .card(padding: 14)
        .disabled(store.busy != nil || store.asking || checking)
        .task {
            let c = ProviderSettings.saved(kind)
            do { key = try ProviderCredential.read(endpoint: ProviderSettings.credentialID(c)) ?? "" }
            catch { status = error.localizedDescription }
        }
    }
    private func discover() async {
        checking = true; status = nil
        defer { checking = false }
        do {
            let provider = try HTTPModelProvider(configuration: configuration, apiKey: key)
            models = try await provider.models()
            if model.isEmpty { model = models.first ?? "" }
            status = models.isEmpty ? "Connected; no models listed. Load one in your server, or enter a model ID manually."
                : "Connected · \(models.count) models. Discovery does not verify tool support; you can also enter an ID manually."
        } catch { status = error.localizedDescription }
    }
}
