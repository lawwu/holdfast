import SwiftUI

struct ModelDownloadProgressView: View {
    let progress: ModelDownloadProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if progress.phase == .downloading {
                HStack {
                    Text(progress.fraction.map { "\(Int($0 * 100))%" } ?? "Downloading…")
                    Spacer(minLength: 4)
                    Text(progress.speedLabel)
                }
                ProgressView(value: progress.fraction)
                Text(progress.timeLabel).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(progress.summary)
                }
            }
        }
        .font(Theme.caption2).monospacedDigit()
        .frame(width: 180, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.summary)
        .help(progress.summary)
    }
}
