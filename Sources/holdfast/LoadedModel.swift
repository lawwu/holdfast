import Foundation

/// Owns cache lifetime, coalesced loading, and stale-load refusal. Callers retain
/// the returned model for their entire use; dropping the cache never releases a
/// model still held by a caller. Loading a different model then waits for that use
/// to end (reported as busy, rather than allocating two sets of weights).
final class LoadedModel<Value: AnyObject>: @unchecked Sendable {
    struct Busy: LocalizedError { var errorDescription: String? { "The answer model is still in use. Wait for current work to finish." } }
    private let lock = NSLock()
    private let releaseUnused: @Sendable () -> Void
    init(releaseUnused: @escaping @Sendable () -> Void = {}) { self.releaseUnused = releaseUnused }
    private var cached: Value?
    private weak var resident: Value?
    private var residentID: String?
    private var generation = UUID()
    private var loading: (id: String, generation: UUID, task: Task<Value, Error>)?

    var loadedID: String? { lock.withLock { cached == nil ? nil : residentID } }
    func unload() {
        lock.withLock {
            generation = UUID()
            cached = nil
            loading?.task.cancel()
            if resident == nil && loading == nil { releaseUnused() }
        }
    }

    func value(for id: String, load: @escaping @Sendable () async throws -> Value) async throws -> Value {
        try Task.checkCancellation()
        while true {
            let decision: (value: Value?, task: Task<Value, Error>?, generation: UUID?, same: Bool) = try lock.withLock {
                if let cached, residentID == id { return (cached, nil, nil, true) }
                if let loading { return (nil, loading.task, loading.generation, loading.id == id && loading.generation == generation) }
                cached = nil
                if resident != nil { throw Busy() }
                releaseUnused()
                generation = UUID()
                let token = generation
                let task = Task { try await load() }
                residentID = id
                loading = (id, token, task)
                return (nil, task, token, true)
            }
            if let value = decision.value { return value }
            let result = await decision.task!.result
            let accepted: Bool = lock.withLock {
                if loading?.generation == decision.generation {
                    loading = nil
                    if case .success(let value) = result {
                        resident = value
                        // Keep the original load identity even when this is a waiter for another model.
                        if generation == decision.generation {
                            cached = value
                        }
                    }
                }
                return generation == decision.generation
            }
            try Task.checkCancellation()
            if !decision.same { continue }
            guard accepted else { throw CancellationError() }
            return try result.get()
        }
    }
}
