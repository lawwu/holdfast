import Foundation
import MLXLMCommon
import ModelProviders

/// Compatibility name for the version 1 native/Pi wire protocol.
public typealias MLXProtocol = Inference

extension Inference.Tool {
        var wire: ToolSpec {
            ["type": "function", "function": ["name": name, "description": description,
                "parameters": Self.sendable(parameters)] as [String: any Sendable]]
        }
        private static func sendable(_ value: ModelJSON) -> any Sendable {
            switch value {
            case .null: return NSNull()
            case .bool(let v): return v
            case .int(let v): return v
            case .double(let v): return v
            case .string(let v): return v
            case .array(let v): return v.map(sendable)
            case .object(let v): return v.mapValues(sendable)
            }
        }
}
extension Inference.Message {
        var normalized: Self {
            var m = self
            if m.reasoning == "" { m.reasoning = nil }
            if m.calls == [] { m.calls = nil }
            m.calls = m.calls?.map { c in
                var c = c
                if let value = try? JSONDecoder().decode(ModelJSON.self, from: Data(c.arguments.utf8)) {
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                    if let data = try? encoder.encode(value) { c.arguments = String(decoding: data, as: UTF8.self) }
                }
                return c
            }
            return m
        }
}
extension Inference.Generation {
        func parameters() throws -> GenerateParameters {
            guard (maxTokens ?? 2000) > 0, (maxTokens ?? 2000) <= 32768,
                  (temperature ?? 0.7).isFinite, (temperature ?? 0.7) >= 0,
                  (topP ?? 0.8) > 0, (topP ?? 0.8) <= 1, (topK ?? 20) >= 0,
                  (presencePenalty ?? 0).isFinite else { throw Inference.Failure("Invalid generation parameters") }
            return GenerateParameters(maxTokens: maxTokens ?? 2000, temperature: temperature ?? 0.7,
                                      topP: topP ?? 0.8, topK: topK ?? 20, presencePenalty: presencePenalty ?? 0)
        }
}
