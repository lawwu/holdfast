import Foundation

/// Holdfast's data policy is independent of the inference provider. Loopback
/// servers may proxy other machines, so counseling is restricted to embedded LocalMLX.
enum ModelPrivacy {
    nonisolated(unsafe) static var keptLocal = false
    static func touchesCounseling(_ chunks: [Chunk]) -> Bool { chunks.contains { Profile.isCounseling($0.relPath) } }
}
