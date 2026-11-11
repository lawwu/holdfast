import Foundation

@main struct ModelProfileTests {
    static func main() throws {
        let qwen = ModelProfile.automatic(for: "mlx-community/Qwen3.8-27B-4bit")
        let gemma = ModelProfile.automatic(for: "mlx-community/gemma-4-e4b-it-4bit")
        precondition(qwen.topP != gemma.topP && qwen.topK != gemma.topK)
        precondition(!qwen.thinking && qwen.contextTokens == 32768)
        var custom = qwen; custom.contextTokens = 65536; custom.maxOutputTokens = 4096; custom.thinking = true
        let restored = try JSONDecoder().decode(ModelProfile.self, from: JSONEncoder().encode(custom))
        precondition(restored == custom && restored.generation.maxTokens == 4096)
        precondition(restored.templateContext["enable_thinking"] as? Bool == true)
        for invalid in [-1, 0, 16384, 999999] {
            var profile = qwen; profile.maxOutputTokens = invalid
            do { _ = try profile.validated(); preconditionFailure("Accepted invalid output limit") } catch {}
        }
        var invalid = qwen; invalid.temperature = .nan
        do { _ = try invalid.validated(); preconditionFailure("Accepted NaN") } catch {}
        precondition(ModelIdentity.family("mlx-community/Qwen3.8-27B-4bit") == ModelIdentity.family("mlx-community/Qwen3.8-27B-8bit"))
        precondition(ModelIdentity.family("mlx-community/Qwen3.5-4B-4bit") != ModelIdentity.family("mlx-community/Qwen3.5-9B-4bit"))
        precondition(ModelIdentity.family("mlx-community/gemma-4-26b-a4b-it-4bit") == "gemma-4-26b-a4b-it")
        precondition(ModelIdentity.precision("Qwen-4-bit") == "4-bit")
        precondition(ModelIdentity.precision("model") == nil)
        print("PASS: model defaults, profile serialization, invalid settings, precision grouping")
    }
}
