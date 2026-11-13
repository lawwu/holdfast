import Foundation
import Combine

/// One transfer at a time across answer, search and speech models. Completed and
/// partial files survive relaunch; interrupted jobs are offered for explicit resume.
@MainActor
final class ModelDownloads: ObservableObject {
    enum State: String, Codable { case queued = "Queued", downloading = "Downloading", paused = "Paused", failed = "Failed", ready = "Ready" }
    enum FollowUp: String, Codable { case selectAnswer, prepareMeaningSearch }
    struct Item: Identifiable, Codable {
        var id: String
        var name: String
        var state: State = .queued
        var progress = ModelDownloadProgress()
        var error: String?
        var followUps: [FollowUp]?
    }
    typealias Operation = @MainActor (@escaping @Sendable (ModelDownloadProgress) async -> Void) async throws -> Void
    @Published private(set) var items: [Item] = []
    private var operations: [String: Operation] = [:]
    private var waiters: [String: [CheckedContinuation<Void, Error>]] = [:]
    private var active: String?
    private var worker: Task<Void, Never>?
    private var cancelled: Set<String> = []
    private let defaults: UserDefaults
    private let resolve: ((String) -> Operation)?
    init(defaults: UserDefaults = .standard, resolve: ((String) -> Operation)? = nil) {
        self.resolve = resolve
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
    func run(id: String, name: String, followUp: FollowUp? = nil, operation: @escaping Operation) async throws {
        try await withCheckedThrowingContinuation { continuation in
            waiters[id, default: []].append(continuation)
            var actions = item(id)?.followUps ?? []
            if let followUp, !actions.contains(followUp) { actions.append(followUp) }
            if active == id || item(id)?.state == .queued {
                update(id) { $0.followUps = actions }; persist(); return
            }
            operations[id] = operation
            if let index = items.firstIndex(where: { $0.id == id }) { items[index] = Item(id: id, name: name, followUps: actions) }
            else { items.append(Item(id: id, name: name, followUps: actions)) }
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
    func resume(_ id: String) {
        guard active != id, let item = item(id), [.paused, .failed].contains(item.state),
              let operation = operations[id] ?? resolve?(id) else { return }
        Task { try? await run(id: id, name: item.name, operation: operation) }
    }
    var progress: [String: ModelDownloadProgress] {
        Dictionary(uniqueKeysWithValues: items.filter { [.queued, .downloading].contains($0.state) }.map { ($0.id, $0.progress) })
    }
    var errors: [String: String] {
        Dictionary(uniqueKeysWithValues: items.compactMap { item in item.error.map { (item.id, $0) } })
    }
    /// Deliver only validated installations. An unavailable caller leaves intent
    /// pending; accepting an action acknowledges it durably. Selection and index
    /// preparation are idempotent if a crash occurs before acknowledgement.
    func deliverFollowUps(accept: (String, FollowUp) -> Bool) {
        for item in items where item.state == .ready {
            for action in item.followUps ?? [] where accept(item.id, action) {
                update(item.id) { $0.followUps?.removeAll { $0 == action } }
                persist()
            }
        }
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
