import Foundation
import Hub
import HuggingFace

enum ModelDownloader {
    private static let patterns = ["*.json", "*.safetensors", "*.jinja", "*.txt", "*.model"]

    static func download(repo: String, source: ModelDownloadSource, to modelsDirectory: URL,
                         progress: @escaping @Sendable (Double) -> Void) async throws {
        let hub = HubApi(downloadBase: modelsDirectory, cache: nil,
                         hfToken: source.token, endpoint: source.endpoint)
        // HubApi's empty-token override suppresses credentials on metadata
        // requests, but its file client still sends an empty Bearer header.
        // Use an explicit no-auth client for anonymous mirrors.
        if source.token == "" {
            guard let id = HuggingFace.Repo.ID(rawValue: repo), let host = URL(string: source.endpoint) else {
                throw ModelDownloadSource.Failure("The model repository or endpoint is invalid.")
            }
            let client = HubClient(host: host, tokenProvider: .none, cache: nil)
            let dir = modelsDirectory.appendingPathComponent("models/\(repo)")
            let files = try await hub.getFilenames(from: Hub.Repo(id: repo), matching: patterns)
            guard files.contains("config.json") else {
                throw ModelDownloadSource.Failure("The model repository did not list config.json. Check the endpoint in Settings → Downloads.")
            }
            for (index, filename) in files.enumerated() {
                try Task.checkCancellation()
                guard !filename.hasPrefix("/"), !filename.contains("\\"),
                      !filename.components(separatedBy: "/").contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) else {
                    throw ModelDownloadSource.Failure("The model repository listed an invalid file path.")
                }
                let fileProgress = Progress(totalUnitCount: 1)
                let observation = fileProgress.observe(\.fractionCompleted) { p, _ in
                    progress((Double(index) + p.fractionCompleted) / Double(files.count))
                }
                defer { observation.invalidate() }
                _ = try await client.downloadFile(at: filename, from: id,
                                                   to: dir.appendingPathComponent(filename), progress: fileProgress)
                progress(Double(index + 1) / Double(files.count))
            }
            try finish(dir)
            return
        }
        let dir = try await hub.snapshot(from: repo, matching: patterns) { p in
            progress(p.fractionCompleted)
        }
        try finish(dir)
    }

    private static func finish(_ dir: URL) throws {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("config.json").path) else {
            throw ModelDownloadSource.Failure("The download did not include config.json. Check the endpoint in Settings → Downloads and the model repository.")
        }
        try Data().write(to: dir.appendingPathComponent(".complete"), options: .atomic)
    }
}
