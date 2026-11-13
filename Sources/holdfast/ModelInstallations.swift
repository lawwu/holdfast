import Foundation

/// App-owned installation policy shared by new requests and recovered jobs.
/// A job becomes ready only after its model-kind validation has succeeded.
@MainActor enum ModelInstallations {
    static func operation(for id: String) -> ModelDownloads.Operation {
        { update in
            if let model = TranscriptionModel.allCases.first(where: { "audio:" + $0.id == id }) {
                let source = try ModelDownloadSource.current()
                let patterns = model.required.map { $0.hasSuffix(".mlmodelc") ? $0 + "/*" : $0 }
                try await ModelDownloader.files(repo: model.repository.rawValue, source: source, to: model.folder,
                    matching: patterns, required: model.required, progress: update)
                guard model.isDownloaded else { throw ModelDownloadSource.Failure("The speech model download is incomplete. Try downloading again.") }
            } else {
                let custom = CustomLocalModels.find(id)
                if let custom {
                    guard custom.source == .huggingFace else { throw HoldfastError("Local folders are used in place.") }
                    _ = try await CustomModelImport.inspectRepository(custom.location)
                }
                try await MLXBackend.download(repo: id, progress: update)
                if let custom {
                    guard let directory = MLXBackend.modelDir(repo: custom.id) else { throw HoldfastError("The downloaded model is incomplete.") }
                    _ = try await CustomModelImport.inspectFolder(directory)
                }
                if id == Reranker.repo { Reranker.unload() }
            }
            try Task.checkCancellation()
        }
    }

    static func download(_ id: String, name: String, followUp: ModelDownloads.FollowUp? = nil) async throws {
        try await ModelDownloads.shared.run(id: id, name: name, followUp: followUp, operation: operation(for: id))
    }
}

@MainActor extension ModelDownloads {
    static let shared = ModelDownloads(resolve: { ModelInstallations.operation(for: $0) })
}
