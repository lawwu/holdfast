import Foundation
import Hub
import HuggingFace

enum ModelDownloader {
    private static let patterns = ["*.json", "*.safetensors", "*.jinja", "*.txt", "*.model"]

    static func download(repo: String, source: ModelDownloadSource, to modelsDirectory: URL,
                         progress: @escaping @Sendable (ModelDownloadProgress) async -> Void) async throws {
        let dir = modelsDirectory.appendingPathComponent("models/\(repo)")
        let marker = dir.appendingPathComponent(".complete")
        if FileManager.default.fileExists(atPath: marker.path) { try FileManager.default.removeItem(at: marker) }
        try await files(repo: repo, source: source, to: dir, matching: patterns,
                        required: ["config.json"], progress: progress)
        try Task.checkCancellation()
        try Data().write(to: marker, options: .atomic)
    }

    /// Shared by LocalMLX and Core ML speech models. The same endpoint and
    /// credential rules apply, and progress counts bytes for the selected files.
    static func files(repo: String, source: ModelDownloadSource, to directory: URL,
                      matching patterns: [String], required: [String],
                      progress: @escaping @Sendable (ModelDownloadProgress) async -> Void) async throws {
        guard let id = HuggingFace.Repo.ID(rawValue: repo), let host = URL(string: source.endpoint) else {
            throw ModelDownloadSource.Failure("The model repository or endpoint is invalid.")
        }
        await progress(ModelDownloadProgress())
        let hub = HubApi(downloadBase: directory, cache: nil, hfToken: source.token, endpoint: source.endpoint)
        let token: TokenProvider = source.token.map { $0.isEmpty ? .none : .fixed(token: $0) } ?? .environment
        let client = HubClient(host: host, tokenProvider: token, cache: nil)
        let files = try await hub.getFilenames(from: Hub.Repo(id: repo), matching: patterns).sorted()
        guard !files.isEmpty, required.allSatisfy({ item in files.contains { $0 == item || $0.hasPrefix(item + "/") } }) else {
            throw ModelDownloadSource.Failure("The repository is missing required model files. Check Settings → Downloads and try again.")
        }
        guard files.allSatisfy({ !$0.hasPrefix("/") && !$0.contains("\\") && !$0.components(separatedBy: "/").contains(where: { $0 == "." || $0 == ".." || $0.isEmpty }) }) else {
            throw ModelDownloadSource.Failure("The model repository listed an invalid file path.")
        }
        var metadata: [String: HubApi.FileMetadata] = [:]
        for file in files {
            try Task.checkCancellation()
            let url = host.appendingPathComponent(repo).appendingPathComponent("resolve/main").appendingPathComponent(file)
            metadata[file] = try await hub.getFileMetadata(url: url)
        }
        let transfer = DownloadTransfer(sizes: metadata.mapValues { $0.size.map(Int64.init) })
        await progress(transfer.snapshot())
        let heartbeat = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                await progress(transfer.snapshot())
            }
        }
        do {
            for file in files {
                try Task.checkCancellation()
                let target = directory.appendingPathComponent(file)
                let meta = directory.appendingPathComponent(".cache/huggingface/download/\(file).metadata")
                let remote = metadata[file]!
                let cached = try? hub.readDownloadMetadata(metadataPath: meta)
                let size = (try? target.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                if let size, let expected = remote.size, size == expected,
                   let etag = remote.etag, !etag.isEmpty, cached?.etag == etag {
                    transfer.finish(file, bytes: Int64(size), cached: true)
                    continue
                }
                let counter = Progress(totalUnitCount: 0)
                transfer.start(file, progress: counter)
                _ = try await client.downloadFile(at: file, from: id, to: target, progress: counter, transport: .lfs)
                let actual = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                if let expected = remote.size, actual != expected {
                    throw ModelDownloadSource.Failure("The download of \(file) is incomplete. Try downloading again.")
                }
                if let etag = remote.etag, !etag.isEmpty {
                    try hub.writeDownloadMetadata(commitHash: remote.commitHash ?? "", etag: etag, metadataPath: meta)
                }
                transfer.finish(file, bytes: Int64(actual), cached: false)
            }
        } catch {
            heartbeat.cancel()
            await heartbeat.value
            throw error
        }
        heartbeat.cancel()
        await heartbeat.value
        var final = transfer.snapshot()
        final.phase = .checking
        await progress(final)
    }
}
