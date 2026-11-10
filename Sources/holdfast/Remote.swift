import Foundation

/// Holdfast's data policy is independent of the inference provider. Loopback
/// servers may proxy other machines, so private is restricted to embedded LocalMLX.
enum ModelPrivacy {
    nonisolated(unsafe) static var keptLocal = false
    static func touchesPrivateNotes(_ chunks: [Chunk]) -> Bool { chunks.contains { Profile.isPrivate($0.relPath) } }
}
