import Foundation
import ModelProviders

@main struct ProviderTests {
    static func main() async throws {
        let args = CommandLine.arguments
        let mode = args[1], address = args[2], kind = ServerKind(rawValue: args[3])!
        for (base, expected) in [("http://localhost:1234", "/v1/models"), ("https://example.test/proxy/v1/", "/proxy/v1/models")] {
            let path = try ServerConfiguration(kind: .custom, baseURL: base).endpoint("models").path
            assert(path == expected)
        }
        for base in ["file:///tmp/test", "https://key@example.test", "https://example.test?key=x", "http://example.test/#key"] {
            do { _ = try ServerConfiguration(kind: .custom, baseURL: base).endpoint("models"); fatalError("accepted invalid endpoint") }
            catch {}
        }
        let c = ServerConfiguration(kind: kind, baseURL: address, model: "test-model")
        let provider = try HTTPModelProvider(configuration: c, apiKey: "test-secret")
        if mode == "models" {
            let models = try await provider.models(); assert(models == ["test-model"])
        } else {
            let call = Inference.Call(id: "prior", name: "typed", arguments: #"{"count":3,"enabled":true,"value":null,"items":["a",2]}"#)
            let request = Inference.Request(model: "test-model", system: "test", messages: [
                .init(role: "user", text: "Hello"), .init(role: "assistant", text: "", calls: [call]),
                .init(role: "tool", text: "previous", id: "prior", name: "typed")],
                tools: [.init(name: "typed", description: "typed schema", parameters: .object(["type": .string("object")]))])
            if mode == "cancel" {
                let task = Task { try await provider.respond(to: request) { _ in } }
                try await Task.sleep(for: .milliseconds(150)); task.cancel()
                do { _ = try await task.value; fatalError("cancellation succeeded") }
                catch { assert(Task.isCancelled == false) }
            } else if mode == "error" {
                do { _ = try await provider.respond(to: request) { _ in }; fatalError("accepted unsafe reply") }
                catch { assert(!error.localizedDescription.contains("test-secret")) }
            } else {
                let reply = try await provider.respond(to: request) { _ in }
                assert(reply.text == "Hello 🌿\u{2028}world")
                assert(reply.reasoning == "thought")
                assert(reply.calls.count == 1 && reply.calls[0].name == "typed")
                let value = try JSONDecoder().decode(ModelJSON.self, from: Data(reply.calls[0].arguments.utf8))
                assert(value == .object(["count": .int(3), "enabled": .bool(true), "value": .null, "items": .array([.string("a"), .int(2)])]))
                assert(reply.usage.promptTokens == 10 && reply.usage.outputTokens == 5)
            }
        }
        print("PASS \(kind.rawValue) \(mode) \(address)")
    }
}
