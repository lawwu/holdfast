import Foundation

struct ModelDownloadProgress: Codable, Sendable {
    enum Phase: String, Codable { case preparing, downloading, checking }
    var phase: Phase = .preparing
    var completedBytes: Int64 = 0
    var totalBytes: Int64?
    var bytesPerSecond: Double?
    var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }
    var remainingSeconds: Double? {
        guard phase == .downloading, let totalBytes, let bytesPerSecond, bytesPerSecond > 0 else { return nil }
        return Double(max(0, totalBytes - completedBytes)) / bytesPerSecond
    }
    var summary: String {
        switch phase {
        case .preparing: return "Checking download size…"
        case .checking: return "Checking files…"
        case .downloading:
            let percent = fraction.map { "\(Int($0 * 100))%" } ?? "Downloading"
            return "\(percent) · \(speedLabel) · \(timeLabel)"
        }
    }
    var speedLabel: String {
        guard let bytesPerSecond, bytesPerSecond > 0 else { return "Waiting for data…" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }
    var timeLabel: String {
        guard let seconds = remainingSeconds, seconds.isFinite else { return "Estimating time…" }
        if seconds < 60 { return "About \(max(1, Int(ceil(seconds))))s left" }
        if seconds < 3600 { return "About \(Int(ceil(seconds / 60))) min left" }
        return String(format: "About %.1f hr left", seconds / 3600)
    }
}

/// Samples transferred bytes, excluding files already on disk. A rolling window
/// makes pauses and changing download speeds visible without invented estimates.
struct DownloadMeter {
    private var samples: [(time: Double, bytes: Int64)] = []
    mutating func snapshot(completed: Int64, total: Int64?, transferred: Int64,
                           now: Double = ProcessInfo.processInfo.systemUptime) -> ModelDownloadProgress {
        if let last = samples.last, transferred < last.bytes { samples = [] }
        samples.append((now, transferred))
        while samples.count > 2, samples[1].time < now - 5 { samples.removeFirst() }
        let first = samples[0]
        let elapsed = now - first.time
        let rate = elapsed >= 0.5 ? Double(max(0, transferred - first.bytes)) / elapsed : nil
        return ModelDownloadProgress(phase: .downloading, completedBytes: completed,
                                     totalBytes: total, bytesPerSecond: rate)
    }
}

/// Progress is updated by the downloader and sampled by one heartbeat task.
final class DownloadTransfer: @unchecked Sendable {
    private let lock = NSLock()
    private var sizes: [String: Int64?]
    private var done: Int64 = 0
    private var transferred: Int64 = 0
    private var active: (String, Progress)?
    private var meter = DownloadMeter()
    init(sizes: [String: Int64?]) { self.sizes = sizes }
    func start(_ file: String, progress: Progress) { lock.withLock { active = (file, progress) } }
    func finish(_ file: String, bytes: Int64, cached: Bool) {
        lock.withLock {
            sizes[file] = bytes
            done += bytes
            if !cached { transferred += bytes }
            active = nil
        }
    }
    func snapshot() -> ModelDownloadProgress {
        lock.withLock {
            var current: Int64 = 0
            if let (file, progress) = active {
                current = max(0, progress.completedUnitCount)
                if progress.totalUnitCount > 0 { sizes[file] = progress.totalUnitCount }
            }
            let known = sizes.values.compactMap { $0 }
            let total: Int64? = known.count == sizes.count ? known.reduce(0, +) : nil
            return meter.snapshot(completed: done + current, total: total, transferred: transferred + current)
        }
    }
}
