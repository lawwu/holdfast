import Foundation

@main struct ModelDownloadProgressTests {
    static func main() {
        var meter = DownloadMeter()
        let initial = meter.snapshot(completed: 900, total: 1000, transferred: 0, now: 0)
        precondition(initial.bytesPerSecond == nil && initial.fraction == 0.9)
        let next = meter.snapshot(completed: 950, total: 1000, transferred: 50, now: 1)
        precondition(next.bytesPerSecond == 50 && next.remainingSeconds == 1, "Cached bytes must not inflate transfer speed")
        for second in 2...8 { _ = meter.snapshot(completed: 950, total: 1000, transferred: 50, now: Double(second)) }
        let stalled = meter.snapshot(completed: 950, total: 1000, transferred: 50, now: 9)
        precondition(stalled.bytesPerSecond == 0 && stalled.remainingSeconds == nil)
        let unknown = meter.snapshot(completed: 980, total: nil, transferred: 80, now: 10)
        precondition(unknown.fraction == nil && unknown.remainingSeconds == nil)

        let transfer = DownloadTransfer(sizes: ["config": 10, "weights": 990])
        transfer.finish("config", bytes: 10, cached: true)
        precondition(transfer.snapshot().fraction == 0.01, "Small files must not dominate progress")
        let bytes = Progress(totalUnitCount: 990)
        transfer.start("weights", progress: bytes)
        bytes.completedUnitCount = 490
        precondition(transfer.snapshot().completedBytes == 500)
        precondition(transfer.snapshot().fraction == 0.5)
        transfer.finish("weights", bytes: 990, cached: false)
        precondition(transfer.snapshot().fraction == 1)
        print("PASS: byte weighting, cached bytes, speed, ETA, stalls and unknown totals")
    }
}
