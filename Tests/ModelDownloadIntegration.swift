import Foundation

@main struct ModelDownloadIntegration {
    static func main() async {
        do {
            let source = try ModelDownloadSource.resolve(savedEndpoint: ModelDownloadSource.defaultEndpoint,
                environment: ProcessInfo.processInfo.environment, savedToken: { _ in nil })
            try await ModelDownloader.download(repo: "test/tiny", source: source,
                to: URL(fileURLWithPath: CommandLine.arguments[1]), progress: { value in
                    if let data = try? JSONEncoder().encode(value), let json = String(data: data, encoding: .utf8) {
                        print(json)
                    }
                })
            print("Downloaded")
        } catch {
            FileHandle.standardError.write(Data("\(error)\n".utf8))
            exit(1)
        }
    }
}
