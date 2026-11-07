import AppKit
import SwiftUI

// MARK: - Listen, in the window
//
// The same session as `mackb listen` (Listen.swift): pick a call or app, everything the Mac plays,
// the microphone or a stream; lines appear as they become final, words still settling in grey.
// When it stops, the transcript is kept in the vault's state folder and handed to the drop folder,
// so the Inbox shows where the model proposes to file it, like any dropped document.
// The app asks macOS for System Audio Recording and the microphone as itself (Info.plist says why).

@MainActor
final class Listener: ObservableObject {
    static let shared = Listener()

    enum Source: String, CaseIterable, Identifiable {
        case app = "A call or app", system = "All Mac audio", mic = "Microphone", url = "A stream"
        var id: String { rawValue }
    }

    struct AudioApp: Identifiable, Hashable {
        var name: String
        var playing: Bool
        var id: String { name }
    }

    @Published private(set) var lines: [Segment] = []
    @Published private(set) var pending = ""
    @Published private(set) var status: String?
    @Published private(set) var started: Date?
    @Published private(set) var source = ""
    @Published private(set) var outcome: Listen.Outcome?
    @Published private(set) var error: String?
    @Published private(set) var stopping = false
    @Published private(set) var recent: [URL] = []
    @Published private(set) var active = false

    private var feed: Listen.Feed?

    func start(_ input: Listen.Input, title: String?, file: Bool) {
        guard !active else { return }
        lines = []
        pending = ""
        outcome = nil
        error = nil
        stopping = false
        started = nil
        status = "Starting…"
        source = input.source
        active = true
        let feed = Listen.Feed()
        self.feed = feed
        // Handlers run on the session's tasks; the main queue keeps their order.
        let h = Listen.Handlers(
            line: { s in
                DispatchQueue.main.async {
                    let l = Listener.shared
                    l.lines.append(s)
                    if l.status?.hasPrefix("only silence") == true { l.status = nil }  // speech arrived after all
                }
            },
            pending: { p in DispatchQueue.main.async { Listener.shared.pending = p } },
            status: { m in DispatchQueue.main.async { Listener.shared.status = m } },
            began: { DispatchQueue.main.async { Listener.shared.started = Date() } })
        Task.detached {
            do {
                let o = try await Listen.session(input, title: title, out: nil, filing: file ? .dropFolder : .none,
                                                 maxSeconds: nil, feed: feed, h)
                await MainActor.run { Listener.shared.finish(o, nil) }
            } catch {
                await MainActor.run { Listener.shared.finish(nil, error) }
            }
        }
    }

    func stop() {
        guard active, !stopping else { return }
        stopping = true
        status = "Finishing: transcribing the last few seconds…"
        feed?.stop()
    }

    private func finish(_ o: Listen.Outcome?, _ e: Error?) {
        active = false
        feed = nil
        stopping = false
        started = nil
        pending = ""
        outcome = o
        error = e.map { "\($0)" }
        status = o.flatMap { $0.lines == 0 ? "Heard no speech in \(formatTime($0.seconds)) of audio; nothing was saved." : nil }
        refreshRecent()
    }

    func refreshRecent() { recent = Listen.recent() }

    /// Listed after apps that are playing, before everything else.
    static let callApps: Set<String> = ["zoom.us", "microsoft teams", "facetime", "webex", "slack", "discord", "google meet",
                                        "google chrome", "safari", "arc", "firefox", "microsoft edge"]

    /// Running apps that have opened audio (a call app opens it when the call starts): playing, then call apps.
    static func audioApps() -> [AudioApp] {
        let procs = SystemAudio.processes()
        var found: [String: Bool] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let bundle = app.bundleIdentifier?.lowercased(), let name = app.localizedName,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { continue }
            let mine = procs.filter { $0.pid == app.processIdentifier || $0.bundleID.lowercased().hasPrefix(bundle) }
            if !mine.isEmpty { found[name] = (found[name] ?? false) || mine.contains(where: \.playing) }
        }
        func rank(_ a: AudioApp) -> Int { a.playing ? 0 : callApps.contains(a.name.lowercased()) ? 1 : 2 }
        return found.map { AudioApp(name: $0.key, playing: $0.value) }
            .sorted { (rank($0), $0.name.lowercased()) < (rank($1), $1.name.lowercased()) }
    }
}

/// "Listening · 03:12" with a red dot: on the Listen page and in the sidebar from any other page.
struct ListeningBadge: View {
    @ObservedObject private var listener = Listener.shared
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Color.red).frame(width: 8, height: 8)
            Text(listener.stopping ? "Finishing…" : listener.started == nil ? "Starting…" : "Listening")
                .font(Theme.caption.weight(.semibold))
            if let s = listener.started {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(formatTime(ctx.date.timeIntervalSince(s))).font(Theme.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct ListenView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var listener = Listener.shared
    @AppStorage("listenSource") private var source: Listener.Source = .app
    @AppStorage("listenApp") private var app = ""
    @AppStorage("listenMic") private var withMic = true
    @AppStorage("listenURL") private var url = ""
    @AppStorage("listenFile") private var fileIt = true
    @State private var apps: [Listener.AudioApp] = []
    @State private var title = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Listen").font(Theme.title2)
                    Text("Transcribe a call, another app, the microphone or a stream as it plays. Transcribed on this Mac.")
                        .font(Theme.callout).foregroundStyle(.secondary)
                }
                if listener.active { live } else { setup }
                if !listener.active, listener.outcome != nil || listener.error != nil || listener.status != nil { result }
                if !listener.recent.isEmpty { recent }
            }
            .padding(.horizontal, 28).padding(.vertical, 26)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            refreshApps()
            listener.refreshRecent()
        }
    }

    // MARK: setup

    var canStart: Bool {
        switch source {
        case .app: return !app.isEmpty
        case .url: return !url.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Listen to", selection: $source) {
                ForEach(Listener.Source.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch source {
            case .app:
                HStack {
                    if apps.isEmpty {
                        Text("No app has opened audio yet. Start the call first, then refresh.")
                            .font(Theme.callout).foregroundStyle(.secondary)
                    } else {
                        Picker("App", selection: $app) {
                            ForEach(apps) { a in Text(a.playing ? "\(a.name) · playing" : a.name).tag(a.name) }
                        }
                        .frame(maxWidth: 360)
                    }
                    Button { refreshApps() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                Toggle("Include my microphone (your side of the call)", isOn: $withMic)
            case .system:
                Text("Everything this Mac plays: calls, videos, other apps.").font(Theme.callout).foregroundStyle(.secondary)
                Toggle("Include my microphone", isOn: $withMic)
            case .mic:
                Text("The Mac's microphone: a room, a lesson, your own notes.").font(Theme.callout).foregroundStyle(.secondary)
            case .url:
                TextField("https://…/live.m3u8, or a file path", text: $url).textFieldStyle(.roundedBorder).font(Theme.body)
            }

            TextField("Title (optional)", text: $title).textFieldStyle(.roundedBorder).font(Theme.body)
            Toggle(Config.inPlace ? "File the transcript when it ends (proposed in the Inbox)" : "Save the transcript as a source when it ends",
                   isOn: $fileIt)

            HStack(spacing: 12) {
                Button { start() } label: { Label("Start Listening", systemImage: "waveform") }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canStart)
                    .keyboardShortcut(.return, modifiers: .command)
                Text(source == .app || withMic && source == .system
                     ? "A call's transcript records everyone on it: ask them first."
                     : "macOS asks once for permission the first time.")
                    .font(Theme.caption).foregroundStyle(.secondary)
            }
            if store.backend == .remote, fileIt {
                Label("Filing sends the transcript to \(Remote.host); counseling stays here.", systemImage: "network")
                    .font(Theme.caption).foregroundStyle(.orange)
            }
        }
        .card()
    }

    func refreshApps() {
        apps = Listener.audioApps()
        if !apps.contains(where: { $0.name == app }) { app = apps.first?.name ?? "" }
    }

    func start() {
        let t = title.trimmingCharacters(in: .whitespaces)
        let input: Listen.Input
        switch source {
        case .app: input = .system(app: app, mic: withMic, mute: false)
        case .system: input = .system(app: nil, mic: withMic, mute: false)
        case .mic: input = .mic
        case .url: input = .url(url.trimmingCharacters(in: .whitespaces), realtime: false)
        }
        listener.start(input, title: t.isEmpty ? nil : t, file: fileIt)
    }

    // MARK: live

    var live: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ListeningBadge().fixedSize()
                Text(listener.source).font(Theme.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button { listener.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .disabled(listener.stopping)
                    .keyboardShortcut(".", modifiers: .command)
            }
            if let s = listener.status { Text(s).font(Theme.caption).foregroundStyle(.secondary) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if listener.lines.isEmpty && listener.pending.isEmpty {
                            Text("Lines appear here once they're final, about 10–25 seconds behind the speaker.")
                                .font(Theme.callout).foregroundStyle(.tertiary)
                        }
                        ForEach(Array(listener.lines.enumerated()), id: \.offset) { _, s in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(formatTime(s.start)).font(Theme.caption.monospacedDigit()).foregroundStyle(.secondary)
                                Text(s.text).font(Theme.body).textSelection(.enabled)
                            }
                        }
                        if !listener.pending.isEmpty {
                            Text(listener.pending).font(Theme.body).foregroundStyle(.tertiary)
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
                .frame(minHeight: 280, maxHeight: 480)
                .onChange(of: listener.lines.count) { proxy.scrollTo("end", anchor: .bottom) }
                .onChange(of: listener.pending) { proxy.scrollTo("end", anchor: .bottom) }
            }
        }
        .card(highlighted: true)
    }

    // MARK: after

    var result: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let e = listener.error {
                ErrorBanner(text: e)
            } else if let o = listener.outcome, o.lines > 0 {
                Label("\(o.lines) lines from \(formatTime(o.seconds)) of audio", systemImage: "checkmark.circle.fill")
                    .font(Theme.headline).foregroundStyle(.green)
                if let f = o.filed { Text(f).font(Theme.callout).foregroundStyle(.secondary) }
                HStack {
                    if let t = o.transcript {
                        Button("Show Transcript in Finder") { NSWorkspace.shared.activateFileViewerSelecting([t]) }
                    }
                    if o.filed?.hasPrefix("Sent to the Inbox") == true {
                        Button("Open Inbox") { store.pane = .inbox }
                    }
                }
            } else if let s = listener.status {
                Text(s).font(Theme.callout).foregroundStyle(.secondary)
            }
        }
        .card(padding: 14)
    }

    var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent transcripts").font(Theme.headline)
            ForEach(listener.recent, id: \.self) { u in
                HStack {
                    Image(systemName: "waveform").foregroundStyle(Theme.accent)
                    Text(Self.label(u)).font(Theme.callout).lineLimit(1)
                    Spacer()
                    Button("Open") { NSWorkspace.shared.open(u) }.buttonStyle(.borderless)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([u]) }.buttonStyle(.borderless)
                }
            }
        }
        .card(padding: 14)
    }

    /// "20261107-115859-family-meeting.md" → "2026-11-07 11:58 · family meeting"
    static func label(_ u: URL) -> String {
        let n = u.deletingPathExtension().lastPathComponent
        let parts = n.split(separator: "-", maxSplits: 2).map(String.init)
        guard parts.count == 3, parts[0].count == 8, parts[1].count == 6 else { return n }
        let d = parts[0], t = parts[1]
        let when = "\(d.prefix(4))-\(d.dropFirst(4).prefix(2))-\(d.suffix(2)) \(t.prefix(2)):\(t.dropFirst(2).prefix(2))"
        return when + " · " + parts[2].replacingOccurrences(of: "-", with: " ")
    }
}
