import Foundation

@main struct ModelDownloadSourceTests {
    static func expect(_ value: Bool, _ message: String) throws {
        if !value { throw ModelDownloadSource.Failure("TEST FAILED: " + message) }
    }

    static func main() throws {
        let mirror = "https://company.jfrog.io/artifactory/api/huggingfaceml/hf-remote"
        try expect(ModelDownloadSource.normalize("  \n") == ModelDownloadSource.defaultEndpoint, "blank resets to Hugging Face")
        try expect(ModelDownloadSource.normalize(" \(mirror)///\n") == mirror, "preserves Artifactory prefix, removes trailing slashes")
        try expect(ModelDownloadSource.normalize("HTTPS://COMPANY.JFROG.IO/path/") == "https://company.jfrog.io/path", "canonical host and scheme")
        try expect(ModelDownloadSource.normalize("http://localhost:8765/mirror/") == "http://localhost:8765/mirror", "local mirror with port")
        for bad in ["company.jfrog.io/mirror", "ftp://host/models", "https:///", "https://a b/path",
                    "https://user:secret@host/path", "https://host/path?token=secret", "https://host/path#fragment"] {
            do {
                _ = try ModelDownloadSource.normalize(bad)
                throw ModelDownloadSource.Failure("TEST FAILED: accepted an invalid endpoint")
            } catch let error as ModelDownloadSource.Failure {
                try expect(!error.description.hasPrefix("TEST FAILED"), error.description)
                try expect(!error.description.contains("secret"), "validation does not echo credentials")
            }
        }
        let saved = try ModelDownloadSource.resolve(savedEndpoint: mirror + "/", environment: [:]) { endpoint in
            try expect(endpoint == mirror, "Keychain lookup uses the complete normalized endpoint")
            return "mirror-token"
        }
        try expect(saved.endpoint == mirror && saved.token == "mirror-token", "saved settings apply")
        let environment = try ModelDownloadSource.resolve(savedEndpoint: mirror, environment: [
            "HF_ENDPOINT": "https://other.example/api/huggingface/team/", "HF_TOKEN": " env-token\n"
        ]) { _ in throw ModelDownloadSource.Failure("Must not read Keychain when HF_TOKEN is set") }
        try expect(environment.endpoint == "https://other.example/api/huggingface/team"
                   && environment.token == "env-token", "environment overrides settings")
        let anonymous = try ModelDownloadSource.resolve(savedEndpoint: mirror, environment: [:]) { _ in nil }
        try expect(anonymous.token == "", "custom mirrors do not inherit a cached Hugging Face credential")
        let changed = try ModelDownloadSource.resolve(savedEndpoint: mirror, environment: ["HF_ENDPOINT": "https://other.example"]) {
            $0 == mirror ? "mirror-token" : nil
        }
        try expect(changed.token == "", "changing endpoints does not reuse a saved token")
        let standard = try ModelDownloadSource.resolve(savedEndpoint: "", environment: ["HF_TOKEN": " ", "HF_ENDPOINT": " "]) { _ in nil }
        try expect(standard.endpoint == ModelDownloadSource.defaultEndpoint && standard.token == nil, "default Hugging Face discovery is preserved")
        do {
            _ = try ModelDownloadSource.resolve(savedEndpoint: mirror, environment: ["HF_ENDPOINT": "invalid"]) { _ in nil }
            throw ModelDownloadSource.Failure("TEST FAILED: invalid environment silently fell back")
        } catch let error as ModelDownloadSource.Failure {
            try expect(!error.description.hasPrefix("TEST FAILED"), error.description)
        }
        try modelFiles()
        print("PASS: model endpoint validation, credential selection, and complete-download lookup")
    }

    static func modelFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let models = root.appendingPathComponent("downloads"), repo = "org/model"
        let own = models.appendingPathComponent("models/\(repo)")
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        func lookup() -> URL? { ModelFiles.directory(repo: repo, modelsDirectory: models, home: root) }
        try expect(lookup() == nil, "empty model directory is not ready")
        try Data("{}".utf8).write(to: own.appendingPathComponent("config.json"))
        try expect(lookup() == nil, "partial download is not ready")
        try Data().write(to: own.appendingPathComponent(".complete"))
        try expect(lookup()?.path == own.path, "app download is found")
        let snapshots = root.appendingPathComponent(".cache/huggingface/hub/models--org--model/snapshots")
        let cached = snapshots.appendingPathComponent("a-complete")
        try FileManager.default.createDirectory(at: cached, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: snapshots.appendingPathComponent("z-incomplete"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: cached.appendingPathComponent("config.json"))
        try expect(lookup()?.path == cached.path, "existing Hugging Face cache takes precedence, skipping empty snapshots")
        try expect(ModelFiles.directory(repo: repo, modelsDirectory: models, home: root,
                                        validate: { $0.path == own.path })?.path == own.path,
                   "custom validation skips incomplete cache snapshots and finds a complete download")
        try FileManager.default.removeItem(at: cached)
        try expect(lookup()?.path == own.path, "incomplete cache does not hide a completed app download")
        try FileManager.default.removeItem(at: own.appendingPathComponent("config.json"))
        try expect(lookup() == nil, "stale completion marker alone is not enough")
    }
}
