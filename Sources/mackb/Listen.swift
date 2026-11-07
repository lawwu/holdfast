import AppKit
import AVFoundation
import FluidAudio
import Foundation

// MARK: - Live transcription (`mackb listen`)
//
// Transcribes audio while it is still arriving: a livestream (or anything else ffmpeg can open),
// the microphone, or raw audio piped in from another program. FluidAudio's sliding-window manager
// runs the same Parakeet model as file transcription over 15 s windows (2 s before, an 11 s chunk,
// 2 s after), so a line is printed once its words can no longer change: about 10–25 s after they
// were spoken. When the audio ends, the whole transcript is kept in the state folder and filed like
// a dropped document (a proposal in the Inbox, or a source note in a managed vault).
//
// Composable on purpose: raw 16 kHz mono s16le on stdin works with any program that can produce
// audio, finished lines go to stdout one per line (or JSON events with --json), and everything
// else (model loading, progress, the filing result) goes to stderr.

enum Listen {
    enum Input {
        case stdin
        /// A stream URL or a file path, opened by ffmpeg. `realtime` reads a file at playing speed
        /// (ffmpeg -re), as if it were live.
        case url(String, realtime: Bool)
        case mic
        /// What the Mac plays (`app` nil) or one app's audio (SystemAudio.swift), with the microphone
        /// mixed in when `mic` is set: both sides of a call. `mute` keeps the tapped audio off the speakers.
        case system(app: String?, mic: Bool, mute: Bool)

        var source: String {
            switch self {
            case .stdin: return "stdin"
            case .url(let s, _): return s
            case .mic: return "microphone"
            case .system(let app, let mic, _): return (app.map { "\($0) (app audio)" } ?? "system audio") + (mic ? " + microphone" : "")
            }
        }
    }

    /// What stdin must carry, and what ffmpeg is asked to produce: 16 kHz mono, signed 16-bit little-endian.
    static let sampleRate = 16_000.0
    /// Audio goes to the recognizer in slices of this many samples (0.5 s at 16 kHz).
    static let sliceSamples = 8_000
    /// HTTP streams drop now and then; ffmpeg reconnects for up to this many seconds.
    static let reconnectSeconds = 10
    /// System or app audio that is still exactly silent after this long gets a permission hint.
    static let silenceWarningSeconds = 12.0

    static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    // MARK: lines from token revisions

    /// Turns the manager's token revisions into finished transcript lines. Only words the manager
    /// marks stable (irrevocable) make a line, and the last line of those stays open until a later
    /// line starts or the audio ends, so a printed line never changes.
    struct LineBuilder {
        private(set) var tokens: [TokenTiming] = []
        private(set) var stable = 0
        private(set) var emitted = 0

        mutating func apply(_ u: SlidingWindowTokenUpdate) -> [Segment] {
            let keep = min(u.revision.retainedTokenCount, tokens.count)
            tokens = Array(tokens.prefix(keep)) + u.tokens
            stable = min(u.revision.stableTokenCount, tokens.count)
            return closed(terminal: u.revision.isTerminal)
        }

        /// Everything heard so far, once the audio has ended.
        mutating func finishAll() -> [Segment] {
            stable = tokens.count
            return closed(terminal: true)
        }

        private mutating func closed(terminal: Bool) -> [Segment] {
            let segs = segments(fromTokens: Array(tokens.prefix(stable)))
            let done = terminal ? segs.count : max(segs.count - 1, 0)
            guard done > emitted else { return [] }
            defer { emitted = done }
            return Array(segs[emitted..<done])
        }

        /// Heard but not printed yet: the open line plus words that may still change.
        var pendingText: String {
            let open = segments(fromTokens: Array(tokens.prefix(stable))).dropFirst(emitted).map(\.text)
            let rest = tokens.dropFirst(stable).map { $0.token.replacingOccurrences(of: "▁", with: " ") }.joined()
            return (open.joined(separator: " ") + " " + rest).trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: audio in

    /// A stream of audio buffers that `stop()` ends at once, even while a reader is blocked on a pipe.
    final class Feed: @unchecked Sendable {
        let stream: AsyncStream<AVAudioPCMBuffer>
        let cont: AsyncStream<AVAudioPCMBuffer>.Continuation
        var onStop: [() -> Void] = []
        private var stopped = false
        private let lock = NSLock()

        init() {
            var c: AsyncStream<AVAudioPCMBuffer>.Continuation!
            stream = AsyncStream(bufferingPolicy: .unbounded) { c = $0 }
            cont = c
        }

        func stop() {
            lock.lock()
            let first = !stopped
            stopped = true
            lock.unlock()
            guard first else { return }
            onStop.forEach { $0() }
            cont.finish()
        }
    }

    /// Reads raw 16 kHz mono s16le from a file handle on its own thread.
    static func readPCM(_ fh: FileHandle, into feed: Feed) {
        let t = Thread {
            var carry = Data()
            while true {
                guard let d = try? fh.read(upToCount: sliceSamples * 2), !d.isEmpty else { break }
                carry.append(d)
                let whole = carry.count - carry.count % 2
                if whole == 0 { continue }
                if let b = buffer(fromS16LE: carry.prefix(whole)) { feed.cont.yield(b) }
                carry = Data(carry.dropFirst(whole))
            }
            feed.cont.finish()
        }
        t.start()
    }

    static func buffer(fromS16LE d: Data) -> AVAudioPCMBuffer? {
        let n = d.count / 2
        guard n > 0, let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { return nil }
        b.frameLength = AVAudioFrameCount(n)
        let out = b.floatChannelData![0]
        d.withUnsafeBytes { raw in
            for i in 0..<n { out[i] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))) / 32768 }
        }
        return b
    }

    /// ffmpeg turns a stream URL or file into raw audio on a pipe; its errors go straight to stderr.
    static func startFFmpeg(_ src: String, realtime: Bool, into feed: Feed) throws {
        guard let ffmpeg = findTool("ffmpeg") else {
            throw MacKBError("Listening to a stream needs ffmpeg. Install it with Homebrew (brew install ffmpeg), then try again.")
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        var a = ["-nostdin", "-loglevel", "error"]
        if src.hasPrefix("http://") || src.hasPrefix("https://") {
            a += ["-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", String(reconnectSeconds)]
        }
        if realtime { a.append("-re") }
        p.arguments = a + ["-i", src, "-vn", "-ac", "1", "-ar", String(Int(sampleRate)), "-f", "s16le", "-"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.standardError
        try p.run()
        feed.onStop.append { if p.isRunning { p.terminate() } }
        readPCM(out.fileHandleForReading, into: feed)
    }

    /// The default input device through AVAudioEngine. A command-line run uses the terminal app's
    /// microphone permission.
    static func requireMic() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else { throw micDenied }
        default: throw micDenied
        }
    }

    /// Audio the Mac plays, all of it or one app's, through a Core Audio process tap
    /// (SystemAudio.swift), with the microphone mixed in when asked.
    static func startSystem(app: String?, mic: Bool, mute: Bool, into feed: Feed, say: (String) -> Void) async throws -> SystemAudio.Capture {
        var processes: [AudioObjectID]?
        if let app {
            let found = SystemAudio.find(app)
            guard !found.isEmpty else {
                let playing = Set(SystemAudio.processes().filter(\.playing).map(\.name)).sorted()
                throw MacKBError("no app matching \"\(app)\" has opened audio yet. Start the call or playback first, then try again."
                    + (playing.isEmpty ? "" : " Playing now: \(playing.joined(separator: ", ")).")
                    + " (mackb listen --apps lists them; --system takes everything the Mac plays.)")
            }
            say("tapping \(Set(found.map(\.name)).sorted().joined(separator: ", "))")
            processes = found.map(\.object)
        }
        switch SystemAudio.audioCapturePermission() {
        case .granted, .unknown: break
        case .denied: throw SystemAudio.captureDenied
        case .notAsked:
            say("asking macOS for permission to record system audio (a dialog appears for the app running mackb)…")
            guard await SystemAudio.requestAudioCapture() else { throw SystemAudio.captureDenied }
        }
        if mic { try await requireMic() }
        let cap = try SystemAudio.Capture(processes: processes, mic: mic, mute: mute) { feed.cont.yield($0) }
        feed.onStop.append { cap.stop() }
        return cap
    }

    /// Runs this same `listen` inside Holdfast.app (`open -n -g -W`), whose Info.plist says why it
    /// records audio, so macOS asks Holdfast for System Audio Recording (and the microphone) instead
    /// of handing a terminal silence. Its output comes back through two FIFOs; Ctrl-C is passed on,
    /// and the app's run finishes the transcript as usual. Returns the exit status for the CLI.
    static func relayThroughApp(_ listenArgs: [String]) throws -> Int32 {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.lawrencewu.mackb") else {
            throw MacKBError("Recording another app's audio runs inside Holdfast.app, which asks macOS for permission. Build it with scripts/make_app.sh and open it once.")
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mackb-listen-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let outPath = dir.appendingPathComponent("out").path, errPath = dir.appendingPathComponent("err").path
        guard mkfifo(outPath, 0o600) == 0, mkfifo(errPath, 0o600) == 0 else { throw MacKBError("couldn't create pipes to Holdfast.app") }

        let token = UUID().uuidString
        var pass = listenArgs
        if let i = pass.firstIndex(of: "--out"), i + 1 < pass.count { pass[i + 1] = URL(fileURLWithPath: pass[i + 1]).path }  // relative to here
        var env: [String] = []
        for (k, v) in ProcessInfo.processInfo.environment where k.hasPrefix("MACKB_") { env += ["--env", "\(k)=\(v)"] }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", "-g", "-W", "--stdout", outPath, "--stderr", errPath] + env
            + ["-a", app.path, "--args", "listen"] + pass + ["--relay-token", token]
        log("running the capture inside Holdfast.app, so macOS asks Holdfast for permission (\(app.path))")
        try p.run()

        let copying = DispatchGroup()
        for (path, dest) in [(outPath, FileHandle.standardOutput), (errPath, FileHandle.standardError)] {
            copying.enter()
            DispatchQueue.global().async {
                defer { copying.leave() }
                guard let fh = FileHandle(forReadingAtPath: path) else { return }  // blocks until the app opens it
                while let d = try? fh.read(upToCount: 4096), !d.isEmpty { dest.write(d) }
            }
        }
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let signals = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            s.setEventHandler { if let pid = pid(withArgument: token) { kill(pid, SIGINT) } }
            s.resume()
            return s
        }
        p.waitUntilExit()
        signals.forEach { $0.cancel() }
        // If the app never opened a pipe, open it here so its reader sees the end.
        for path in [outPath, errPath] {
            let fd = open(path, O_WRONLY | O_NONBLOCK)
            if fd >= 0 { close(fd) }
        }
        _ = copying.wait(timeout: .now() + 5)
        return p.terminationStatus
    }

    /// The process started with this argument (the relaunched listen), via pgrep.
    static func pid(withArgument token: String) -> pid_t? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", token]
        let out = Pipe()
        p.standardOutput = out
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let s = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return s.split(separator: "\n").compactMap { pid_t($0) }.first { $0 != getpid() }
    }

    static func startMic(into feed: Feed) async throws {
        try await requireMic()
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { throw MacKBError("no microphone found") }
        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { buf, _ in
            // The tap can reuse its buffer: hand on a copy.
            guard let c = AVAudioPCMBuffer(pcmFormat: buf.format, frameCapacity: buf.frameLength), let src = buf.floatChannelData,
                  let dst = c.floatChannelData else { return }
            c.frameLength = buf.frameLength
            for ch in 0..<Int(buf.format.channelCount) { dst[ch].update(from: src[ch], count: Int(buf.frameLength)) }
            feed.cont.yield(c)
        }
        engine.prepare()
        try engine.start()
        feed.onStop.append { input.removeTap(onBus: 0); engine.stop() }
    }

    static let micDenied = MacKBError(
        "Microphone access is off. Allow it in System Settings → Privacy & Security → Microphone for the app running mackb, then try again.")

    // MARK: run

    struct Event: Encodable {
        var type: String  // "line", "partial", "done"
        var start: Double?
        var time: String?
        var text: String?
        var duration: Double?
        var lines: Int?
        var transcript: String?
        var filed: String?
    }

    static func emit(_ e: Event) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.withoutEscapingSlashes]
        if let d = try? enc.encode(e), let s = String(data: d, encoding: .utf8) { print(s) }
        fflush(stdout)
    }

    /// What a session reports as it goes: the command line prints it, the app shows it on its Listen page.
    /// Called from background tasks, in order.
    struct Handlers {
        var line: (Segment) -> Void
        var pending: (String) -> Void
        var status: (String) -> Void
        /// The audio is flowing (after the model loaded and any permission prompt).
        var began: () -> Void = {}
    }

    /// When it ends: no filing, file now (the CLI loads a model and proposes), or hand the transcript
    /// to the drop folder (the app, whose drop watcher files it into the Inbox like any document).
    enum Filing { case none, now, dropFolder }

    struct Outcome {
        var lines: Int
        var seconds: Double
        var transcript: URL?
        var filed: String?
    }

    /// One listening session, from loading the model to filing the transcript. `feed.stop()` ends it
    /// early; the words already heard are still transcribed and kept.
    static func session(_ input: Input, title: String?, out: URL?, filing: Filing, maxSeconds: Double?, feed: Feed,
                        _ h: Handlers) async throws -> Outcome {
        let choice = Prefs.transcription
        h.status("loading \(choice.name) for live transcription (first run downloads the CoreML model)…")
        let models = try await AsrModels.downloadAndLoad(version: choice == .parakeetV2 ? .v2 : .v3)
        let config: SlidingWindowAsrConfig = choice == .parakeetV2
            ? SlidingWindowAsrConfig.default.applying(tdtConfig: TdtConfig(blankId: 1024))  // v2's blank token
            : .default
        let asr = SlidingWindowAsrManager(config: config)
        try await asr.loadModels(models)
        let updates = await asr.tokenUpdates  // subscribe before any audio
        if case .mic = input { try await asr.startStreaming(source: .microphone) } else { try await asr.startStreaming(source: .system) }

        let started = Date()
        let name = title ?? defaultTitle(input, started)
        let journal = try journalURL(started, name)
        try ("# \(name)\n\nSource: \(input.source)\n\n## Transcript (still listening)\n\n").write(to: journal, atomically: true, encoding: .utf8)

        var capture: SystemAudio.Capture?
        do {
            switch input {
            case .stdin: readPCM(.standardInput, into: feed)
            case .url(let s, let rt): try startFFmpeg(s, realtime: rt, into: feed)
            case .mic: try await startMic(into: feed)
            case .system(let app, let mic, let mute): capture = try await startSystem(app: app, mic: mic, mute: mute, into: feed, say: h.status)
            }
        } catch {
            try? FileManager.default.removeItem(at: journal)
            await asr.cleanup()
            throw error
        }
        h.began()
        h.status("listening to \(input.source): lines appear once they are final, about 10–25 s behind.")
        if case .system = input { h.status("A call's transcript records the other people on it too: ask them first.") }

        let journalHandle = try FileHandle(forWritingTo: journal)
        journalHandle.seekToEndOfFile()
        let printer = Task { () -> (lines: [Segment], error: Error?) in
            var b = LineBuilder()
            var lines: [Segment] = []
            var lastPending = ""
            func show(_ segs: [Segment]) {
                for s in segs {
                    lines.append(s)
                    h.line(s)
                    journalHandle.write(Data("[\(formatTime(s.start))] \(s.text)\n".utf8))
                }
            }
            var failure: Error?
            do {
                for try await u in updates {
                    show(b.apply(u))
                    let p = b.pendingText
                    if p != lastPending { lastPending = p; h.pending(p) }
                }
            } catch {
                failure = error
            }
            show(b.finishAll())
            h.pending("")
            return (lines, failure)
        }

        var seconds = 0.0
        var warnedSilence = false
        for await buf in feed.stream {
            seconds += Double(buf.frameLength) / buf.format.sampleRate
            await asr.streamAudio(buf)
            if let m = maxSeconds, seconds >= m { break }
            // A tap without permission delivers silence, not an error.
            if let capture, !warnedSilence, seconds > silenceWarningSeconds, capture.peak == 0 {
                warnedSilence = true
                h.status("only silence so far. If something is playing, allow System Audio Recording for the app running mackb "
                    + "(System Settings → Privacy & Security → Screen & System Audio Recording), then start again.")
            }
        }
        feed.stop()
        h.status("finishing: transcribing the last few seconds…")
        var finishError: Error?
        do { _ = try await asr.finish() } catch { finishError = error }
        let (lines, streamError) = await printer.value
        try? journalHandle.close()
        await asr.cleanup()
        if let e = streamError ?? finishError { h.status("transcription stopped early: \(e). Keeping what was heard.") }

        guard !lines.isEmpty else {
            try? FileManager.default.removeItem(at: journal)
            h.status("heard no speech in \(formatTime(seconds)) of audio; nothing saved")
            return Outcome(lines: 0, seconds: seconds, transcript: nil, filed: nil)
        }

        // The whole transcript, kept in the state folder whatever happens to the filing.
        let meta = ["title": name, "source": input.source, "kind": "stream",
                    "recorded": stamp(started, "yyyy-MM-dd HH:mm"), "duration": formatTime(seconds),
                    "transcriber": "\(choice == .parakeetV2 ? "parakeet-tdt-0.6b-v2" : "parakeet-tdt-0.6b-v3") (FluidAudio, live)"]
        let body = "\n# \(name)\n\nSource: \(input.source)\n\n## Transcript\n\n"
            + lines.map { "[\(formatTime($0.start))] \($0.text)\n" }.joined()
        try Note(path: journal, meta: meta, body: body).write()
        if let out { try Note(path: out, meta: meta, body: body).write() }

        var filed: String?
        if filing != .none {
            do { filed = try await fileTranscript(journal, name: name, input: input, seconds: seconds, lines: lines, meta: meta,
                                                  viaDropFolder: filing == .dropFolder, say: h.status) }
            catch { filed = "not filed: \(error)" }
        }
        return Outcome(lines: lines.count, seconds: seconds, transcript: out ?? journal, filed: filed)
    }

    /// `mackb listen`: lines on stdout (or JSON events), progress on stderr, Ctrl-C stops.
    static func run(_ input: Input, title: String?, json: Bool, out: URL?, file: Bool, maxSeconds: Double?) async throws {
        setvbuf(stdout, nil, _IOLBF, 0)  // a line reaches a pipe as soon as it is printed
        let feed = Feed()
        // Ctrl-C (or a kill) ends the audio and keeps everything heard; a second Ctrl-C quits at once.
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        let signals = [SIGINT, SIGTERM].map { sig -> DispatchSourceSignal in
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler {
                log("\nstopping (Ctrl-C again to quit without saving)")
                signal(SIGINT, SIG_DFL)
                feed.stop()
            }
            s.resume()
            return s
        }
        defer { signals.forEach { $0.cancel() }; signal(SIGINT, SIG_DFL); signal(SIGTERM, SIG_DFL) }

        let tty = !json && isatty(STDERR_FILENO) != 0
        func clearStatus() { if tty { FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8)) } }
        let h = Handlers(
            line: { s in
                clearStatus()
                if json { emit(Event(type: "line", start: s.start, time: formatTime(s.start), text: s.text)) }
                else { print("[\(formatTime(s.start))] \(s.text)"); fflush(stdout) }
            },
            pending: { p in
                if json { if !p.isEmpty { emit(Event(type: "partial", text: p)) } }
                else if tty { FileHandle.standardError.write(Data(("\r\u{1B}[2K… " + String(p.suffix(100))).utf8)) }
            },
            status: { m in clearStatus(); log(m) })
        let o = try await session(input, title: title, out: out, filing: file ? .now : .none, maxSeconds: maxSeconds, feed: feed, h)
        if o.lines > 0 {
            log("\(o.lines) lines from \(formatTime(o.seconds)) of audio. Transcript: \(o.transcript?.path ?? "")")
            if let f = o.filed { log(f) }
        }
        if json { emit(Event(type: "done", duration: o.seconds, lines: o.lines, transcript: o.transcript?.path, filed: o.filed)) }
    }

    /// A managed vault keeps the transcript as a source note. An in-place vault files it like any
    /// dropped document: the model proposes where it belongs and the proposal waits in the Inbox.
    static func fileTranscript(_ transcript: URL, name: String, input: Input, seconds: Double, lines: [Segment],
                               meta: [String: String], viaDropFolder: Bool, say: (String) -> Void) async throws -> String {
        if !Config.inPlace {
            let n = try transcriptNote(title: name, source: input.source, kind: "stream", duration: seconds, segments: lines,
                                       extra: ["transcriber": meta["transcriber"] ?? "", "recorded": meta["recorded"] ?? ""])
            return "Saved \(n.relPath)"
        }
        Drop.ensure()
        let dropped = Drop.unique(Drop.dir.appendingPathComponent(transcript.lastPathComponent), ifExists: true)
        try FileManager.default.copyItem(at: transcript, to: dropped)
        if viaDropFolder { return "Sent to the Inbox: the model is proposing where it belongs" }
        say("filing the transcript (the model proposes where it belongs)…")
        let emb = try? await Embedder.load()
        let llm = try await makeBackend()
        do {
            return try await Drop.process(dropped, embedder: emb, llm: llm, model: "listen")
        } catch where !FileManager.default.fileExists(atPath: dropped.path) {
            return "Holdfast (the app) picked it up from the drop folder and is filing it"
        }
    }

    /// Transcripts kept in this vault's state folder, newest first.
    static func recent(limit: Int = 20) -> [URL] {
        let dir = Config.stateDir.appendingPathComponent("listening")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent > $1.lastPathComponent }.prefix(limit).map { $0 }
    }

    static func journalURL(_ started: Date, _ name: String) throws -> URL {
        let dir = Config.stateDir.appendingPathComponent("listening")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let slug = slugify(name).isEmpty ? "transcript" : String(slugify(name).prefix(60))
        return dir.appendingPathComponent("\(stamp(started, "yyyyMMdd-HHmmss"))-\(slug).md")
    }

    static func defaultTitle(_ input: Input, _ started: Date) -> String {
        let when = stamp(started, "yyyy-MM-dd HH:mm")
        switch input {
        case .stdin: return "Live transcript \(when)"
        case .mic: return "Recording \(when)"
        case .system(let app, let mic, _):
            if let app { return "\(app.capitalized) \(mic ? "call" : "audio") \(when)" }
            return "\(mic ? "Meeting" : "Mac audio") \(when)"
        case .url(let s, _):
            if let u = URL(string: s), let host = u.host, !host.isEmpty { return "\(host) livestream \(when)" }
            return URL(fileURLWithPath: s).deletingPathExtension().lastPathComponent
        }
    }

    static func stamp(_ d: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/Los_Angeles")
        f.dateFormat = format
        return f.string(from: d)
    }
}
