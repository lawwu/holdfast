import Foundation

@main struct CustomLocalModelTests {
    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw LocalModelFiles.Failure("TEST FAILED: " + message) }
    }
    static func rejects(_ message: String, _ operation: () throws -> Void) throws {
        do { try operation() } catch let error as LocalModelFiles.Failure {
            try expect(!error.message.hasPrefix("TEST FAILED"), error.message)
            return
        }
        throw LocalModelFiles.Failure("TEST FAILED: " + message)
    }
    static func main() throws {
        try expect(LocalModelFiles.repositoryID("  mlx-community/Example-4bit\n") == "mlx-community/Example-4bit", "repo normalization")
        try expect(LocalModelFiles.repositoryID("https://huggingface.co/owner/model/") == "owner/model", "model URL")
        for input in ["../model", "owner/../model", "owner/model/resolve/main", "owner/model?token=secret", "owner//model",
                      "local:/tmp/model", "https://user:secret@huggingface.co/owner/model", "https://other.example/owner/model",
                      "https://huggingface.co/owner/model/tree/main", "https://huggingface.co/owner/model?token=secret",
                      "https://huggingface.co/owner%2Fmodel", "owner/m odel", "owner/model.git"] {
            try rejects("invalid repository accepted") { _ = try LocalModelFiles.repositoryID(input) }
        }
        let config = Data(#"{"model_type":"qwen3_5"}"#.utf8)
        var files: [String: Int64] = ["config.json": 30, "tokenizer.json": 20, "tokenizer_config.json": 20, "model.safetensors": 128]
        try expect(LocalModelFiles.inspect(configuration: config, files: files).weightBytes == 128, "weight sizes")
        files["model.safetensors"] = -1
        try expect(LocalModelFiles.inspect(configuration: config, files: files).weightBytes == nil, "unknown size remains unknown")
        files["model.safetensors"] = 0
        try rejects("empty weights") { _ = try LocalModelFiles.inspect(configuration: config, files: files) }
        files.removeValue(forKey: "model.safetensors")
        files["model.gguf"] = 100
        try rejects("GGUF is not an MLX checkpoint") { _ = try LocalModelFiles.inspect(configuration: config, files: files) }
        files["model-00001-of-00002.safetensors"] = 100
        try rejects("missing shard without index") { _ = try LocalModelFiles.inspect(configuration: config, files: files) }
        files["unrelated.safetensors"] = 100
        try rejects("unrelated weights cannot replace a missing shard") { _ = try LocalModelFiles.inspect(configuration: config, files: files) }
        files.removeValue(forKey: "unrelated.safetensors")
        let index = Data(#"{"weight_map":{"a":"model-00001-of-00002.safetensors","b":"model-00002-of-00002.safetensors"}}"#.utf8)
        try rejects("missing shard with index") { _ = try LocalModelFiles.inspect(configuration: config, files: files, index: index) }
        files["model-00002-of-00002.safetensors"] = 200
        try expect(LocalModelFiles.inspect(configuration: config, files: files, index: index).weightBytes == 300, "complete shards")
        let badIndex = Data(#"{"weight_map":{"a":"../outside.safetensors"}}"#.utf8)
        try rejects("index must stay inside checkpoint") { _ = try LocalModelFiles.inspect(configuration: config, files: files, index: badIndex) }
        files.removeValue(forKey: "model-00001-of-00002.safetensors")
        files.removeValue(forKey: "model-00002-of-00002.safetensors")
        files["model.safetensors"] = 80
        try expect(LocalModelFiles.inspect(configuration: config, files: files, index: index).weightBytes == 80, "consolidated MLX conversion with stale index")
        files.removeValue(forKey: "tokenizer.json")
        try rejects("missing tokenizer") { _ = try LocalModelFiles.inspect(configuration: config, files: files) }
        try rejects("bad config") { _ = try LocalModelFiles.inspect(configuration: Data("{}".utf8), files: files) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Model with spaces")
        try expect(CustomLocalModels.folderName(folder) == "Model with spaces", "local folder name")
        try expect(CustomLocalModels.folderName(root.appendingPathComponent("models--owner--Model-4bit/snapshots/abc123")) == "Model-4bit", "readable cache snapshot name")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try config.write(to: folder.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("tokenizer.json"))
        try Data("{}".utf8).write(to: folder.appendingPathComponent("tokenizer_config.json"))
        let blob = root.appendingPathComponent("blob")
        try Data(repeating: 7, count: 128).write(to: blob)
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("model.safetensors"), withDestinationURL: blob)
        try expect(LocalModelFiles.inspect(directory: folder).weightBytes == 128, "HF blob symlinks")
        let domain = "app.holdfast.tests.custom-models." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let model = CustomLocalModel(id: "local:test", source: .folder, location: folder.path, name: "Test", modelType: "qwen3_5", weightBytes: 128)
        try CustomLocalModels.add(model, defaults: defaults)
        let duplicate = CustomLocalModel(id: "local:other", source: .folder, location: folder.path, name: "Other", modelType: "qwen3_5", weightBytes: 128)
        try expect(CustomLocalModels.add(duplicate, defaults: defaults).id == model.id, "same folder keeps a stable ID")
        try expect(CustomLocalModels.load(defaults: UserDefaults(suiteName: domain)!) == [model], "choices persist across instances")
        try CustomLocalModels.remove(model.id, defaults: defaults)
        try expect(CustomLocalModels.load(defaults: defaults).isEmpty, "remove choice")
        try expect(Data(contentsOf: blob).count == 128, "removing a choice preserves user's files")
        try FileManager.default.removeItem(at: blob)
        try rejects("broken snapshot symlink") { _ = try LocalModelFiles.inspect(directory: folder) }
        try FileManager.default.moveItem(at: folder, to: root.appendingPathComponent("Moved"))
        try rejects("moved folder") { _ = try LocalModelFiles.inspect(directory: folder) }
        print("PASS: custom repository inputs, checkpoint completeness, symlinks, persistent choices, and non-destructive removal")
    }
}
