import Foundation

struct FileImportActivity: Identifiable {
    enum Outcome { case working, review, added, skipped, failed }
    let id: UUID
    var name: String
    var detail: String
    var outcome: Outcome = .working
    var updated = Date()
    var finished: Bool { outcome != .working }
}
