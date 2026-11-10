import Foundation

/// Local, append-only evidence of what a run asked for and what actually happened.
/// Like Pennant, finalized messages and tool intent/outcome are durable; token deltas
/// are transient. An intent without an outcome is uncertain, never permission to retry.
final class AgentJournal: @unchecked Sendable {
    enum Payload: Codable {
        case configuration(system: String, model: String, tools: [AgentRuntime.ToolSpec], prior: [AgentRuntime.Message])
        case event(AgentRuntime.Event)
    }
    struct Entry: Codable {
        var version = 1
        var sequence: Int
        var timestamp: Date
        var payload: Payload
    }

    let url: URL
    private let file: FileHandle
    private let lock = NSLock()
    private var sequence = 0
    private let encoder = JSONEncoder()

    init(directory: URL, system: String, model: String, tools: [AgentRuntime.ToolSpec], prior: [AgentRuntime.Message]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        url = directory.appendingPathComponent(UUID().uuidString + ".jsonl")
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw AgentRuntime.Failure("Could not create the agent run journal.")
        }
        file = try FileHandle(forWritingTo: url)
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try write(.configuration(system: system, model: model, tools: tools, prior: prior))
    }

    deinit { try? file.close() }

    func append(_ event: AgentRuntime.Event) throws {
        if case .text = event { return }
        try write(.event(event))
    }

    private func write(_ payload: Payload) throws {
        lock.lock(); defer { lock.unlock() }
        let entry = Entry(sequence: sequence, timestamp: Date(), payload: payload)
        var data = try encoder.encode(entry)
        data.append(0x0A)
        try file.write(contentsOf: data)
        try file.synchronize()
        sequence += 1
    }
}
