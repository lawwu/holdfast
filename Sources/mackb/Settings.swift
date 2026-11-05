import AppKit
import SwiftUI

/// Settings window (⌘,): choose the answer model and see the on-device
/// models retrieval and transcription use.
struct SettingsView: View {
    var body: some View {
        TabView {
            ModelSettings()
                .tabItem { Label("Models", systemImage: "cpu") }
            VaultSettings()
                .tabItem { Label("Vault", systemImage: "folder") }
        }
        .frame(width: 560)
        .tint(Theme.accent)
    }
}

// MARK: - Models

/// What each answer backend is, measured on the synthetic case-report eval
/// (eval/results, 2026-11-05) on this Mac.
extension Backend {
    var title: String { self == .mlx ? "Qwen 3.8 27B · 4-bit" : "Qwen 3.8 27B · 8-bit" }
    var runtime: String { self == .mlx ? "MLX, inside the app" : "Ollama server on this Mac" }
    var facts: [(String, String)] {
        switch self {
        case .mlx: return [("memorychip", "~16 GB"), ("gauge.with.dots.needle.67percent", "~11 tok/s"), ("checkmark.seal", "98% on the eval")]
        case .ollama: return [("memorychip", "~28 GB"), ("gauge.with.dots.needle.67percent", "~5 tok/s"), ("checkmark.seal", "78% on the eval*")]
        }
    }
    var note: String {
        switch self {
        case .mlx: return "Recommended. Twice as fast, half the memory; nothing else to run."
        case .ollama: return "Needs the Ollama server running. *Measured before the retrieval fixes."
        }
    }
}

enum ModelStatus: Equatable {
    case checking, ready(String), missing(String)
}

struct ModelSettings: View {
    @EnvironmentObject var store: Store
    @State private var mlxStatus: ModelStatus = .checking
    @State private var ollamaStatus: ModelStatus = .checking
    @State private var mlxLoaded = MLXBackend.isLoaded

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Answer model").font(.headline)
                Text("Writes answers from the passages retrieval finds. Takes effect on the next question.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(Backend.allCases) { b in
                    BackendCard(backend: b, selected: store.backend == b,
                                status: b == .mlx ? mlxStatus : ollamaStatus) {
                        store.backend = b
                        UserDefaults.standard.set(b.rawValue, forKey: "backend")
                    }
                }
            }
            if mlxLoaded && store.backend == .ollama {
                HStack(spacing: 10) {
                    Image(systemName: "memorychip").foregroundStyle(.orange)
                    Text("The MLX model is still in memory (~16 GB).").font(.callout)
                    Spacer()
                    Button("Unload") {
                        MLXBackend.unload()
                        mlxLoaded = false
                    }
                    .disabled(store.busy != nil)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.1)))
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Always on this Mac").font(.headline)
                Text("Retrieval and transcription models. These are fixed for now.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                FixedModelRow(icon: "point.3.connected.trianglepath.dotted", name: "Qwen3-Embedding 0.6B",
                              role: "Finds passages by meaning", present: Config.embedModelDir != nil)
                Divider().padding(.leading, 40)
                FixedModelRow(icon: "arrow.up.arrow.down", name: "Qwen3-Reranker 0.6B · 4-bit",
                              role: "Ranks the candidates; declines when nothing fits", present: Reranker.modelDir != nil)
                Divider().padding(.leading, 40)
                FixedModelRow(icon: "waveform", name: "Parakeet v3",
                              role: "Transcribes recordings (downloads on first use)", present: nil)
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        }
        .padding(24)
        .task { await checkStatus() }
    }

    func checkStatus() async {
        mlxLoaded = MLXBackend.isLoaded
        if let dir = MLXBackend.modelDir {
            mlxStatus = mlxLoaded ? .ready("Loaded") : .ready(dir.path.contains("models--") ? "Downloaded" : "Found")
        } else {
            mlxStatus = .missing("Not downloaded")
        }
        var req = URLRequest(url: Config.ollamaURL.appendingPathComponent("api/tags"))
        req.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = j["models"] as? [[String: Any]] else {
            ollamaStatus = .missing("Ollama not running")
            return
        }
        let names = models.compactMap { $0["name"] as? String }
        ollamaStatus = names.contains(where: { $0.hasPrefix(Config.llmModel) })
            ? .ready("Installed") : .missing("\(Config.llmModel) not installed")
    }
}

struct BackendCard: View {
    var backend: Backend
    var selected: Bool
    var status: ModelStatus
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.secondary.opacity(0.5)))
                    Spacer()
                    StatusBadge(status: status)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(backend.title).font(.callout.weight(.semibold))
                    Text(backend.runtime).font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(backend.facts, id: \.1) { icon, text in
                        Label(text, systemImage: icon).labelStyle(TightLabel())
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                Text(backend.note).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.07) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(selected ? Theme.accent.opacity(0.7) : Color.primary.opacity(hover ? 0.2 : 0.1),
                              lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct StatusBadge: View {
    var status: ModelStatus
    var body: some View {
        switch status {
        case .checking:
            ProgressView().controlSize(.mini)
        case .ready(let s):
            Pill(text: s, icon: "checkmark", color: .green)
        case .missing(let s):
            Pill(text: s, icon: "exclamationmark.triangle", color: .orange)
        }
    }
}

struct FixedModelRow: View {
    var icon: String
    var name: String
    var role: String
    var present: Bool?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.callout.weight(.medium))
                Text(role).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let present {
                StatusBadge(status: present ? .ready("Ready") : .missing("Not downloaded"))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }
}

// MARK: - Vault

struct VaultSettings: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Vault").font(.headline)
                Text("A folder of plain Markdown notes. It can be an Obsidian vault; the search index is a cache inside it.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.vault.lastPathComponent).font(.callout.weight(.semibold))
                    Text(store.vault.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.vault]) }
                Button("Change…") { store.chooseVault() }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
            HStack(spacing: 16) {
                Label("\(store.notes.count) notes", systemImage: "doc.on.doc")
                Label("\(store.indexCounts.chunks) passages indexed", systemImage: "text.alignleft")
                Spacer()
                Button("Rebuild Index") { store.rebuildIndex() }.disabled(store.busy != nil)
            }
            .font(.callout).foregroundStyle(.secondary)
        }
        .padding(24)
    }
}
