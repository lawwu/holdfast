import Foundation

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
