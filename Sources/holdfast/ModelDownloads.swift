import Foundation
import Combine

/// One transfer at a time across answer, search and speech models. Completed and
/// partial files survive relaunch; interrupted jobs are offered for explicit resume.
@MainActor
final class ModelDownloads: ObservableObject {
    static let shared = ModelDownloads()
    enum State: String, Codable { case queued = "Queued", downloading = "Downloading", paused = "Paused", failed = "Failed", ready = "Ready" }
    struct Item: Identifiable, Codable {
        var id: String
        var name: String
        var state: State = .queued
        var progress = ModelDownloadProgress()
        var error: String?
    }
    typealias Operation = @MainActor (@escaping @Sendable (ModelDownloadProgress) async -> Void) async throws -> Void
    @Published private(set) var items: [Item] = []
    private var operations: [String: Operation] = [:]
    private var waiters: [String: [CheckedContinuation<Void, Error>]] = [:]
    private var active: String?
    private var worker: Task<Void, Never>?
    private var cancelled: Set<String> = []
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "modelDownloads.v1"), let saved = try? JSONDecoder().decode([Item].self, from: data) {
            items = saved.map { value in
                var item = value
                if item.state == .downloading || item.state == .queued { item.state = .paused }
                return item
            }
        }
    }
    func item(_ id: String) -> Item? { items.first { $0.id == id } }
    func run(id: String, name: String, operation: @escaping Operation) async throws {
        try await withCheckedThrowingContinuation { continuation in
            waiters[id, default: []].append(continuation)
            if active == id || item(id)?.state == .queued { return }
            operations[id] = operation
            if let index = items.firstIndex(where: { $0.id == id }) { items[index] = Item(id: id, name: name) }
            else { items.append(Item(id: id, name: name)) }
            persist(); startNext()
        }
    }
    func pause(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), [.queued, .downloading].contains(items[index].state) else { return }
        if active == id { cancelled.insert(id); worker?.cancel() }
        else {
            items[index].state = .paused
            finishWaiters(id, result: .failure(CancellationError())); persist()
        }
    }
    func resume(_ id: String, store: Store) {
        guard active != id, item(id)?.state != .queued else { return }
        if let operation = operations[id] {
            let name = item(id)?.name ?? id
            Task { try? await run(id: id, name: name, operation: operation) }
        } else if let audio = TranscriptionModel.allCases.first(where: { "audio:" + $0.id == id }) { AudioModels.shared.start(audio) }
        else { store.downloadRepo(id) }
    }
    func forget(_ id: String) {
        guard active != id, item(id)?.state != .queued else { return }
        items.removeAll { $0.id == id }; operations[id] = nil; persist()
    }
    private func startNext() {
        guard active == nil, let next = items.first(where: { $0.state == .queued }), let operation = operations[next.id] else { return }
        active = next.id
        update(next.id) { $0.state = .downloading; $0.error = nil }
        worker = Task {
            let result: Result<Void, Error>
            do {
                try await operation { progress in
                    await MainActor.run { self.update(next.id) { $0.progress = progress } }
                }
                try Task.checkCancellation(); result = .success(())
            } catch { result = .failure(error) }
            let paused = cancelled.remove(next.id) != nil
            update(next.id) { item in
                switch result {
                case .success: item.state = .ready
                case .failure(let error):
                    item.state = paused || error is CancellationError ? .paused : .failed
                    item.error = item.state == .failed ? error.localizedDescription : nil
                }
            }
            active = nil; worker = nil
            finishWaiters(next.id, result: result); persist(); startNext()
        }
    }
    private func finishWaiters(_ id: String, result: Result<Void, Error>) {
        let listeners = waiters.removeValue(forKey: id) ?? []
        for listener in listeners { listener.resume(with: result) }
    }
    private func update(_ id: String, _ change: (inout Item) -> Void) {
        if let index = items.firstIndex(where: { $0.id == id }) { change(&items[index]) }
    }
    private func persist() { if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: "modelDownloads.v1") } }
}

/// A user-added folder and shared HF caches are never deleted by Holdfast.
enum ModelStorage {
    static func bytes(at directory: URL) -> Int64 {
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        return files.reduce(Int64(0)) { total, item in
            guard let file = item as? URL, let info = try? file.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), info.isRegularFile == true else { return total }
            return total + Int64(info.fileSize ?? 0)
        }
    }
    static func ownedDirectory(_ repo: String) -> URL? {
        guard CustomLocalModels.find(repo)?.source != .folder else { return nil }
        let components = repo.components(separatedBy: "/")
        guard components.count == 2, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") }) else { return nil }
        let root = Prefs.modelsDir.appendingPathComponent("models").standardizedFileURL.resolvingSymlinksInPath()
        let directory = root.appendingPathComponent(repo).standardizedFileURL
        guard directory.resolvingSymlinksInPath().path == directory.path else { return nil }
        return directory
    }
    static func delete(_ repo: String) throws {
        guard let directory = ownedDirectory(repo) else { throw HoldfastError("This folder is managed outside Holdfast. Use Finder to manage its files.") }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
}
