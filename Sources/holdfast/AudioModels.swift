import Foundation
import Combine
import FluidAudio

enum TranscriptionModel: String, CaseIterable, Identifiable, Sendable {
    case parakeetV3 = "parakeet-v3", parakeetV2 = "parakeet-v2"
    case parakeetUltra = "parakeet-ultra", parakeetRedux = "parakeet-redux"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .parakeetV3: return "Parakeet v3"
        case .parakeetV2: return "Parakeet v2"
        case .parakeetUltra: return "Parakeet Ultra"
        case .parakeetRedux: return "Parakeet Redux"
        }
    }
    var blurb: String {
        switch self {
        case .parakeetV3: return "25 European languages. Recommended default."
        case .parakeetV2: return "English only. For recordings that are all in English."
        case .parakeetUltra: return "Multilingual. Refined from v3 for improved accuracy; a larger download than Redux."
        case .parakeetRedux: return "Multilingual. A smaller, compressed v3 variant for saving disk space. Requires macOS 15 or later."
        }
    }
    var version: AsrModelVersion {
        switch self {
        case .parakeetV3: return .v3
        case .parakeetV2: return .v2
        case .parakeetUltra: return .ultra
        case .parakeetRedux: return .redux
        }
    }
    var repository: Repo {
        switch self {
        case .parakeetV3: return .parakeetV3
        case .parakeetV2: return .parakeetV2
        case .parakeetUltra: return .parakeetUltra
        case .parakeetRedux: return .parakeetRedux
        }
    }
    var folder: URL { AsrModels.defaultCacheDirectory(for: version) }
    var required: [String] {
        let models = self == .parakeetV2 ? ModelNames.ASR.requiredModels : ModelNames.ASR.requiredModelsV3()
        return Array(models).sorted() + [ModelNames.ASR.vocabularyFile]
    }
    var isDownloaded: Bool { AsrModels.modelsExist(at: folder, version: version) }
}

/// A shared download task prevents Settings and Listen from writing the same
/// model concurrently. Loading is explicitly local, so it cannot bypass the
/// configured mirror or silently fall back to a direct Hugging Face download.
@MainActor
final class AudioModels: ObservableObject {
    static let shared = AudioModels()
    @Published private(set) var progress: [String: ModelDownloadProgress] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var available: Set<String> = []
    private var tasks: [String: Task<Void, Error>] = [:]
    init() { refresh() }
    func refresh() { available = Set(TranscriptionModel.allCases.filter(\.isDownloaded).map(\.id)) }
    func start(_ model: TranscriptionModel) { Task { try? await download(model) } }

    func download(_ model: TranscriptionModel) async throws {
        if let task = tasks[model.id] { return try await task.value }
        if model.isDownloaded { refresh(); return }
        progress[model.id] = ModelDownloadProgress()
        errors[model.id] = nil
        let task = Task {
            let source = try ModelDownloadSource.current()
            let patterns = model.required.map { $0.hasSuffix(".mlmodelc") ? $0 + "/*" : $0 }
            try await ModelDownloader.files(repo: model.repository.rawValue, source: source, to: model.folder,
                                            matching: patterns, required: model.required) { value in
                await MainActor.run { self.progress[model.id] = value }
            }
            guard model.isDownloaded else {
                throw ModelDownloadSource.Failure("The speech model download is incomplete. Try downloading again.")
            }
        }
        tasks[model.id] = task
        defer { tasks[model.id] = nil; progress[model.id] = nil; refresh() }
        do { try await task.value }
        catch { errors[model.id] = error.localizedDescription; throw error }
    }

    nonisolated static func load(_ model: TranscriptionModel,
                                status: @escaping @Sendable (String) -> Void = { _ in }) async throws -> AsrModels {
        let updates = Task { @MainActor in
            while !Task.isCancelled {
                if let progress = shared.progress[model.id] { status("\(model.name): \(progress.summary)") }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            }
        }
        do { try await shared.download(model) }
        catch { updates.cancel(); await updates.value; throw error }
        updates.cancel()
        await updates.value
        try Task.checkCancellation()
        status("Preparing \(model.name) on this Mac… First use can take a few minutes.")
        guard model.isDownloaded else {
            throw ModelDownloadSource.Failure("Speech model files are missing. Download the model again in Settings → Transcription.")
        }
        return try await Task.detached { try AsrModels.loadLocal(from: model.folder, version: model.version) }.value
    }
}
