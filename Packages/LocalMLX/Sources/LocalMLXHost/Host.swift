import Darwin
import Foundation
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import LocalMLX
import Tokenizers

private final class Output: @unchecked Sendable {
    private let lock = NSLock()
    func send(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        lock.lock(); defer { lock.unlock() }
        try? FileHandle.standardOutput.write(contentsOf: data + Data([10]))
    }
}

private actor Server {
    let model: String, directory: URL
    let output = Output()
    var engine: MLXSession?
    var active: (id: String, task: Task<Void, Never>)?
    init(model: String, directory: URL) { self.model = model; self.directory = directory }

    func accept(_ data: Data) {
        var id = ""
        do {
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any], let requestID = value["id"] as? String else {
                throw MLXProtocol.Failure("Invalid Swift MLX frame")
            }
            id = requestID
            if value["type"] as? String == "cancel" { if active?.id == id { active?.task.cancel() }; return }
            guard value["type"] as? String == "generate" else { throw MLXProtocol.Failure("Only inference requests are supported") }
            guard active == nil else { throw MLXProtocol.Failure("Swift MLX host is busy") }
            let request = try JSONDecoder().decode(MLXProtocol.Request.self, from: JSONSerialization.data(withJSONObject: value["request"] ?? [:]))
            guard request.model == model, request.version == 1 else { throw MLXProtocol.Failure("Model or protocol mismatch") }
            active = (id, Task { await self.generate(request, id: requestID) })
        } catch { output.send(["type": "response", "id": id, "error": error.localizedDescription]) }
    }

    func generate(_ request: MLXProtocol.Request, id: String) async {
        do {
            try Task.checkCancellation()
            if engine == nil {
                let container = try await LLMModelFactory.shared.loadContainer(from: directory, using: #huggingFaceTokenizerLoader())
                engine = MLXSession(container: container)
            }
            try Task.checkCancellation()
            let reply = try await engine!.respond(to: request) { [output] text in output.send(["type": "delta", "id": id, "text": text]) }
            try Task.checkCancellation()
            output.send(["type": "response", "id": id, "result": try JSONSerialization.jsonObject(with: JSONEncoder().encode(reply))])
        } catch { output.send(["type": "response", "id": id, "error": error.localizedDescription]) }
        active = nil
    }
    func close() async { let task = active?.task; task?.cancel(); await task?.value }
}

@main struct LocalMLXHost {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard args.count == 4, args[0] == "--model", args[2] == "--model-dir" else {
                throw MLXProtocol.Failure("Usage: local-mlx-host --model MODEL_ID --model-dir /absolute/path/to/local/model")
            }
            let directory = URL(fileURLWithPath: args[3])
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path) else {
                throw MLXProtocol.Failure("No local model at \(directory.path); this host does not download models")
            }
            Memory.cacheLimit = 2 << 30
            _ = fcntl(FileHandle.standardOutput.fileDescriptor, F_SETNOSIGPIPE, 1)
            let server = Server(model: args[1], directory: directory)
            let lines = AsyncStream<Data> { continuation in
                DispatchQueue.global().async {
                    var buffer = Data()
                    while true {
                        let data = FileHandle.standardInput.availableData
                        if data.isEmpty { break }
                        buffer.append(data)
                        while let newline = buffer.firstIndex(of: 10) {
                            continuation.yield(Data(buffer[..<newline])); buffer.removeSubrange(...newline)
                        }
                        if buffer.count > 32 * 1024 * 1024 { break }
                    }
                    continuation.finish()
                }
            }
            for await line in lines { await server.accept(line) }
            await server.close()
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1)
        }
    }
}
