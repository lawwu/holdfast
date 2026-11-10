import Foundation

@main struct ModelDownloadIntegration {
    static func main() async {
        do {
            let source = try ModelDownloadSource.resolve(savedEndpoint: ModelDownloadSource.defaultEndpoint,
                environment: ProcessInfo.processInfo.environment, savedToken: { _ in nil })
            try await ModelDownloader.download(repo: "test/tiny", source: source,
                to: URL(fileURLWithPath: CommandLine.arguments[1]), progress: { _ in })
            print("Downloaded")
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}
