import Foundation

/// App-owned choices. A folder reference never copies, moves, or deletes model files.
struct CustomLocalModel: Codable, Identifiable, Equatable, Sendable {
    enum Source: String, Codable, Sendable { case huggingFace, folder }
    let id: String
    let source: Source
    let location: String
    let name: String
    let modelType: String
    let weightBytes: Int64?

    var folder: URL? { source == .folder ? URL(fileURLWithPath: location) : nil }
    var sizeDescription: String {
        weightBytes.map { String(format: "%.1f GB weights", Double($0) / 1_000_000_000) } ?? "Weight size unavailable"
    }
}

enum CustomLocalModels {
    static let preferenceKey = "customLocalModelsV1"

    static func folderName(_ folder: URL) -> String {
        let parent = folder.deletingLastPathComponent()
        let cache = parent.deletingLastPathComponent().lastPathComponent
        if parent.lastPathComponent == "snapshots", cache.hasPrefix("models--") {
            let parts = cache.components(separatedBy: "--")
            if parts.count == 3, !parts[2].isEmpty { return parts[2] }
        }
        return folder.lastPathComponent
    }

    static func load(defaults: UserDefaults = .standard) -> [CustomLocalModel] {
        guard let data = defaults.data(forKey: preferenceKey),
              let models = try? JSONDecoder().decode([CustomLocalModel].self, from: data) else { return [] }
        return models
    }

    @discardableResult
    static func add(_ model: CustomLocalModel, defaults: UserDefaults = .standard) throws -> CustomLocalModel {
        var models = load(defaults: defaults)
        if let existing = models.first(where: { $0.id == model.id || ($0.source == model.source && $0.location == model.location) }) {
            return existing
        }
        models.append(model)
        defaults.set(try JSONEncoder().encode(models), forKey: preferenceKey)
        return model
    }

    static func remove(_ id: String, defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(load(defaults: defaults).filter { $0.id != id }), forKey: preferenceKey)
    }

    static func find(_ id: String) -> CustomLocalModel? { load().first { $0.id == id } }
}
