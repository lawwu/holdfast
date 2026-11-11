import Foundation
import HuggingFace
import LocalMLX
import MLXLLM

enum CustomModelImport {
    static func inspectRepository(_ input: String) async throws -> (String, LocalModelFiles.Inspection) {
        let repo = try LocalModelFiles.repositoryID(input)
        let source = try ModelDownloadSource.current()
        guard let id = HuggingFace.Repo.ID(rawValue: repo), let endpoint = URL(string: source.endpoint) else {
            throw LocalModelFiles.Failure("The model repository or download source is invalid.")
        }
        let token: TokenProvider = source.token.map { $0.isEmpty ? .none : .fixed(token: $0) } ?? .environment
        let client = HubClient(host: endpoint, tokenProvider: token, cache: nil)
        var files: [String: Int64] = [:]
        for try await page in try await client.listAllTree(in: id, recursive: true) {
            try Task.checkCancellation()
            for entry in page.items where entry.type == .file {
                guard LocalModelFiles.safeRelativePath(entry.path) else { throw LocalModelFiles.Failure("The repository lists an invalid file path.") }
                files[entry.path] = entry.effectiveSize.map(Int64.init) ?? -1
            }
        }
        guard let configSize = files["config.json"], configSize <= 4 * 1024 * 1024 else {
            throw LocalModelFiles.Failure("This repository does not contain a usable config.json. Choose an MLX model repository.")
        }
        let data = try await client.downloadContentsOfFile(at: "config.json", from: id)
        var index: Data?
        if files["model.safetensors.index.json"] != nil {
            index = try await client.downloadContentsOfFile(at: "model.safetensors.index.json", from: id)
        }
        let inspection = try LocalModelFiles.inspect(configuration: data, files: files, index: index)
        try await checkArchitecture(inspection)
        return (repo, inspection)
    }

    static func inspectFolder(_ directory: URL) async throws -> LocalModelFiles.Inspection {
        let inspection = try await Task.detached(priority: .userInitiated) {
            try LocalModelFiles.inspect(directory: directory)
        }.value
        try Task.checkCancellation()
        try await checkArchitecture(inspection)
        return inspection
    }

    static func checkArchitecture(_ inspection: LocalModelFiles.Inspection) async throws {
        guard await LLMModelFactory.shared.typeRegistry.contains(inspection.modelType) else {
            throw LocalModelFiles.Failure("This version of LocalMLX does not support the model architecture ‘\(inspection.modelType)’. Try an MLX-compatible model or connect it through Ollama or LM Studio.")
        }
    }
}
