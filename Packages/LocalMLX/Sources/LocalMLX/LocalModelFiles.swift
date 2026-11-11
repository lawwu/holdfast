import Foundation

/// Lightweight checks shared by apps that accept user-supplied MLX checkpoints.
/// This reads metadata, never executes repository code or loads weights into the GPU.
public enum LocalModelFiles {
    public struct Failure: LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
        public init(_ message: String) { self.message = message }
    }

    public struct Inspection: Codable, Sendable, Equatable {
        public let modelType: String
        /// Weight bytes on disk, not a prediction of peak memory use. nil means unknown.
        public let weightBytes: Int64?
    }

    /// Accept a repository ID or its root Hugging Face URL, never a revision/file URL.
    public static func repositoryID(_ input: String) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("://") {
            guard let url = URLComponents(string: value), url.scheme?.lowercased() == "https",
                  url.host?.lowercased() == "huggingface.co", url.port == nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  !url.percentEncodedPath.contains("%") else {
                throw Failure("Use a Hugging Face model URL or an owner/model repository ID, without credentials or a query.")
            }
            value = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ part in
            let s = String(part)
            return s.count <= 96 && s.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
                && !s.contains("..") && !s.contains("--") && !s.hasSuffix(".") && !s.hasSuffix("-") && !s.hasSuffix(".git")
        }) else {
            throw Failure("Enter owner/model, or the model's main Hugging Face page. Links to files, branches, and collections are not model IDs.")
        }
        return value
    }

    public static func safeRelativePath(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0")
            && !path.components(separatedBy: "/").contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// File sizes may be -1 when a server does not provide them.
    public static func inspect(configuration: Data, files: [String: Int64], index: Data? = nil) throws -> Inspection {
        guard configuration.count <= 4 * 1024 * 1024,
              let config = try? JSONSerialization.jsonObject(with: configuration) as? [String: Any],
              let type = config["model_type"] as? String, !type.isEmpty else {
            throw Failure("The model needs a valid config.json with a model_type.")
        }
        guard files.keys.allSatisfy(safeRelativePath) else { throw Failure("The model lists an invalid file path.") }
        guard let tokenizerSize = files["tokenizer.json"], tokenizerSize != 0 else {
            throw Failure("The model needs tokenizer.json. Choose the complete MLX model folder or repository.")
        }
        guard let tokenizerConfigSize = files["tokenizer_config.json"], tokenizerConfigSize != 0 else {
            throw Failure("The model needs tokenizer_config.json. Choose the complete model folder or repository.")
        }
        var weights = files.keys.filter { !$0.contains("/") && $0.hasSuffix(".safetensors") }.sorted()
        if let index {
            guard let object = try? JSONSerialization.jsonObject(with: index) as? [String: Any],
                  let map = object["weight_map"] as? [String: String], !map.isEmpty else {
                throw Failure("The model's weight index is invalid. Choose a complete MLX checkpoint.")
            }
            let indexed = Set(map.values)
            guard indexed.allSatisfy({ safeRelativePath($0) && $0.hasSuffix(".safetensors") }) else {
                throw Failure("The model's weight index contains an invalid file path.")
            }
            if indexed.allSatisfy({ files[$0] != nil }) { weights = indexed.sorted() }
            // Some MLX conversions keep an old shard index alongside one consolidated file.
            else if files["model.safetensors"] != nil { weights = ["model.safetensors"] }
            else { throw Failure("Some weight shards are missing. Finish downloading the model before adding it.") }
        }
        guard !weights.isEmpty else {
            throw Failure("No safetensors weights were found. Choose an MLX checkpoint; GGUF models can use Ollama or LM Studio instead.")
        }
        guard weights.allSatisfy({ files[$0] != 0 }) else {
            throw Failure("A model weight file is empty. Finish downloading the model before adding it.")
        }
        // Detect interrupted sharded downloads even when no index was supplied.
        let shardPattern = try NSRegularExpression(pattern: #"^(.+)-([0-9]+)-of-([0-9]+)\.safetensors$"#)
        var shardGroups: [String: (total: Int, present: Set<Int>)] = [:]
        for name in weights {
            let text = name as NSString
            if let match = shardPattern.firstMatch(in: name, range: NSRange(location: 0, length: text.length)) {
                guard let number = Int(text.substring(with: match.range(at: 2))),
                      let total = Int(text.substring(with: match.range(at: 3))),
                      total > 0, number > 0, number <= total else {
                    throw Failure("The model has invalid weight shard names. Choose a complete MLX checkpoint.")
                }
                let key = text.substring(with: match.range(at: 1)) + "-of-\(total)"
                var group = shardGroups[key] ?? (total, [])
                group.present.insert(number)
                shardGroups[key] = group
            }
        }
        for group in shardGroups.values {
            if group.present.count != group.total {
                throw Failure("Some weight shards are missing. Finish downloading the model before adding it.")
            }
        }
        let sizes = weights.compactMap { files[$0] }
        let bytes = sizes.contains(where: { $0 < 0 }) ? nil : sizes.reduce(Int64(0)) { total, next in
            let sum = total.addingReportingOverflow(next)
            return sum.overflow ? Int64.max : sum.partialValue
        }
        return Inspection(modelType: type, weightBytes: bytes)
    }

    public static func inspect(directory: URL) throws -> Inspection {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard directory.isFileURL, fm.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure("This model folder is unavailable. Reconnect its drive or add its new location.")
        }
        let configURL = directory.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: configURL), data.count <= 4 * 1024 * 1024 else {
            throw Failure("Choose the folder containing config.json, tokenizer.json, and the model's safetensors weights.")
        }
        let indexURL = directory.appendingPathComponent("model.safetensors.index.json")
        let index = fm.fileExists(atPath: indexURL.path) ? try Data(contentsOf: indexURL) : nil
        var names = try fm.contentsOfDirectory(atPath: directory.path)
        if let index, let object = try? JSONSerialization.jsonObject(with: index) as? [String: Any],
           let map = object["weight_map"] as? [String: String] {
            guard map.values.allSatisfy(safeRelativePath) else { throw Failure("The model's weight index contains an invalid file path.") }
            names += map.values
        }
        var files: [String: Int64] = [:]
        for name in Set(names) where safeRelativePath(name) {
            let url = directory.appendingPathComponent(name)
            // Hugging Face snapshots use symlinks to their blob cache; follow those links.
            if let values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               values.isRegularFile == true, let size = values.fileSize { files[name] = Int64(size) }
        }
        return try inspect(configuration: data, files: files, index: index)
    }
}
