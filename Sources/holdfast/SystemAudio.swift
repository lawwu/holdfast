import AppKit
import AVFoundation
import CoreAudio
import Darwin
import Foundation

// MARK: - Audio from other apps (Core Audio process taps, macOS 14.2+)
//
// For `holdfast listen --system` / `--app <name>`: a tap on what the Mac plays (everything, or one
// app's processes), put in a private aggregate device, optionally together with the default
// microphone so both sides of a call land in one transcript. The aggregate's clock is the output
// device's; the microphone gets drift compensation. Every input stream is mixed to mono and handed
// on as Float32 buffers at the aggregate's sample rate (the recognizer resamples to 16 kHz).
//
// Permission: macOS asks once for "System Audio Recording" (System Settings → Privacy & Security →
// Screen & System Audio Recording), for the app that runs holdfast (from a terminal, the terminal).
// Without it the tap delivers silence rather than an error, so `Capture.peak` lets the caller warn.

enum SystemAudio {
    struct AudioProcess {
        var object: AudioObjectID
        var pid: pid_t
        var bundleID: String
        var name: String
        var playing: Bool
    }

    // MARK: property helpers

    static func address(_ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
        -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: s, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func value<T>(_ obj: AudioObjectID, _ s: AudioObjectPropertySelector, _ initial: T) -> T? {
        var a = address(s)
        var v = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    static func string(_ obj: AudioObjectID, _ s: AudioObjectPropertySelector) -> String? {
        var a = address(s)
        var v: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr, let v else { return nil }
        return v.takeRetainedValue() as String
    }

    static func objects(_ obj: AudioObjectID, _ s: AudioObjectPropertySelector) -> [AudioObjectID] {
        var a = address(s)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func processObject(pid: pid_t) -> AudioObjectID? {
        var a = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var p = pid
        var o = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &a, UInt32(MemoryLayout<pid_t>.size), &p, &size, &o) == noErr,
              o != kAudioObjectUnknown else { return nil }
        return o
    }

    // MARK: permission
    //
    // macOS has no public call to ask for "System Audio Recording": an app with
    // NSAudioCaptureUsageDescription is asked when its tap starts, but a command-line tool gets
    // silence. These are the private TCC calls AudioCap and similar tools use, looked up at run
    // time; if they are missing, the caller's silence check still warns.

    enum Permission { case granted, denied, notAsked, unknown }

    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)

    static func audioCapturePermission() -> Permission {
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
        guard let tcc, let sym = dlsym(tcc, "TCCAccessPreflight") else { return .unknown }
        switch unsafeBitCast(sym, to: Preflight.self)("kTCCServiceAudioCapture" as CFString, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .notAsked
        }
    }

    /// Shows macOS's prompt for the app running holdfast; true when allowed.
    static func requestAudioCapture() async -> Bool {
        typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
        guard let tcc, let sym = dlsym(tcc, "TCCAccessRequest") else { return false }
        return await withCheckedContinuation { c in
            unsafeBitCast(sym, to: Request.self)("kTCCServiceAudioCapture" as CFString, nil) { c.resume(returning: $0) }
        }
    }

    static let captureDenied = HoldfastError(
        "Recording system audio isn't allowed for the app running holdfast. Allow it in System Settings → Privacy & Security → "
        + "Screen & System Audio Recording, under System Audio Recording Only (add Terminal, or whichever app you run holdfast from), then try again.")

    // MARK: which processes

    /// Every process Core Audio knows about (anything that has opened audio), and whether it is playing now.
    static func processes() -> [AudioProcess] {
        objects(system, kAudioHardwarePropertyProcessObjectList).map { o in
            let pid = value(o, kAudioProcessPropertyPID, pid_t(0)) ?? 0
            let bundle = string(o, kAudioProcessPropertyBundleID) ?? ""
            let playing = (value(o, kAudioProcessPropertyIsRunningOutput, UInt32(0)) ?? 0) != 0
            return AudioProcess(object: o, pid: pid, bundleID: bundle, name: processName(pid), playing: playing)
        }
    }

    static func processName(_ pid: pid_t) -> String {
        if let n = NSRunningApplication(processIdentifier: pid)?.localizedName { return n }
        var buf = [CChar](repeating: 0, count: 256)
        return proc_name(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : "pid \(pid)"
    }

    /// What `--app` names: a running app (with the processes playing its audio) or, for tools that
    /// aren't apps (ffmpeg, afplay), the processes with exactly that name.
    struct Target {
        var name: String
        var app: NSRunningApplication?
        var query: String
        var processes: [AudioProcess]

        /// The same target's audio processes now (a call app starts new helpers as a call begins).
        func current() -> [AudioProcess] { SystemAudio.processes(for: app, query: query) }
    }

    /// The running app a query names: its bundle ID, its name, or a part of its name that only one
    /// app has. Two apps matching is an error, not a guess: "Music" must not also catch YouTube Music.
    static func app(_ query: String) throws -> NSRunningApplication? {
        let q = query.lowercased()
        let own = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != own }
        if let a = apps.first(where: { $0.bundleIdentifier?.lowercased() == q }) { return a }
        if let a = apps.first(where: { ($0.localizedName ?? "").lowercased() == q }) { return a }
        let partial = apps.filter { ($0.localizedName ?? "").lowercased().contains(q) }
        let names = Set(partial.compactMap(\.localizedName)).sorted()
        if names.count > 1 {
            throw HoldfastError("\"\(query)\" matches several apps: \(names.joined(separator: ", ")). Use the full name or the bundle ID (holdfast listen --apps).")
        }
        return partial.first
    }

    /// An app's audio processes: the app itself and helpers whose bundle ID extends its own
    /// (a browser's renderer); without an app, processes named exactly as asked.
    static func processes(for app: NSRunningApplication?, query: String) -> [AudioProcess] {
        let all = processes()
        guard let app else { return all.filter { $0.name.lowercased() == query.lowercased() } }
        let bundle = app.bundleIdentifier?.lowercased() ?? ""
        return all.filter { p in
            let b = p.bundleID.lowercased()
            return p.pid == app.processIdentifier || (!bundle.isEmpty && (b == bundle || b.hasPrefix(bundle + ".")))
        }
    }

    static func resolve(_ query: String) throws -> Target {
        let a = try app(query)
        return Target(name: a?.localizedName ?? query, app: a, query: query, processes: processes(for: a, query: query))
    }

    /// A name to show for a query (a bundle ID from the Listen page reads as the app's name).
    static func label(_ query: String) -> String {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier?.lowercased() == query.lowercased() }?.localizedName ?? query
    }

    static func inputStreamCount(_ device: AudioObjectID) -> Int {
        var a = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &a, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    static func defaultDevice(_ which: AudioObjectPropertySelector) throws -> (id: AudioObjectID, uid: String) {
        guard let dev = value(system, which, AudioObjectID(kAudioObjectUnknown)), dev != kAudioObjectUnknown,
              let uid = string(dev, kAudioDevicePropertyDeviceUID) else {
            throw HoldfastError(which == kAudioHardwarePropertyDefaultInputDevice ? "no microphone found" : "no audio output device found")
        }
        return (dev, uid)
    }

    // MARK: capture

    /// A tap in a private aggregate device, rebuilt when the default output (or input) device
    /// changes or audio stops arriving, and, for one app, updated as the app starts new audio
    /// processes. Only the tap's stream and, when asked, the microphone's are mixed: an output
    /// device with a microphone of its own (a USB headset, a display) adds input streams of its
    /// own to the aggregate, and those are left out unless that device is the microphone.
    final class Capture {
        private var tapID = AudioObjectID(kAudioObjectUnknown)
        private let desc: CATapDescription
        private var aggregateID = AudioObjectID(kAudioObjectUnknown)
        private var procID: AudioDeviceIOProcID?
        private let io = DispatchQueue(label: "net.lawrencewu.holdfast.listen.io", qos: .userInitiated)
        /// Rebuilds and process updates run here, never on `io` (stopping a device waits for its IO).
        private let control = DispatchQueue(label: "net.lawrencewu.holdfast.listen.control")
        private let lock = NSLock()
        private var loudest: Float = 0
        private var lastIO = Date()
        /// Leading input streams of the aggregate to leave out (the output device's own inputs).
        private var skip = 0
        private var format: AVAudioFormat?
        private var stopped = false
        private var lastRebuild = Date.distantPast
        private var watchdog: DispatchSourceTimer?
        private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
        private let target: Target?
        private let mic: Bool
        private let onEvent: (String) -> Void
        private let onAudio: (AVAudioPCMBuffer) -> Void
        private var tapped: Set<AudioObjectID>

        /// Seconds without audio before the capture is rebuilt.
        static let stallSeconds: TimeInterval = 4
        /// How often an app's audio processes are looked up again.
        static let refreshSeconds: TimeInterval = 1

        /// The loudest sample so far: exactly 0 after several seconds usually means no permission.
        var peak: Float { lock.lock(); defer { lock.unlock() }; return loudest }

        /// `target` nil taps everything the Mac plays (except holdfast itself). `mute` silences the
        /// tapped audio on the speakers while it is captured.
        init(target: Target?, mic: Bool, mute: Bool, onEvent: @escaping (String) -> Void, onAudio: @escaping (AVAudioPCMBuffer) -> Void) throws {
            self.target = target
            self.mic = mic
            self.onEvent = onEvent
            self.onAudio = onAudio
            let ids = target?.processes.map(\.object) ?? []
            tapped = Set(ids)
            if target != nil {
                desc = CATapDescription(stereoMixdownOfProcesses: ids)
            } else {
                let own = SystemAudio.processObject(pid: ProcessInfo.processInfo.processIdentifier)
                desc = CATapDescription(stereoGlobalTapButExcludeProcesses: own.map { [$0] } ?? [])
            }
            desc.uuid = UUID()
            desc.name = "Holdfast listen"
            desc.isPrivate = true
            desc.muteBehavior = mute ? .mutedWhenTapped : .unmuted
            var tap = AudioObjectID(kAudioObjectUnknown)
            let err = AudioHardwareCreateProcessTap(desc, &tap)
            guard err == noErr else { throw HoldfastError("couldn't tap the Mac's audio (Core Audio error \(err))") }
            tapID = tap
            do {
                try control.sync { try build() }
            } catch {
                AudioHardwareDestroyProcessTap(tapID)
                tapID = AudioObjectID(kAudioObjectUnknown)
                throw error
            }
            watch()
        }

        /// Makes the aggregate on today's default devices and starts its IO. On `control`.
        private func build() throws {
            let output = try SystemAudio.defaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice)
            var subs: [[String: Any]] = [[kAudioSubDeviceUIDKey: output.uid]]
            var leave = SystemAudio.inputStreamCount(output.id)
            if mic {
                let input = try SystemAudio.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
                if input.uid == output.uid {
                    leave = 0  // a headset: its inputs are the microphone asked for
                } else {
                    subs.append([kAudioSubDeviceUIDKey: input.uid, kAudioSubDeviceDriftCompensationKey: true])
                }
            }
            let agg: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Holdfast listen",
                kAudioAggregateDeviceUIDKey: "net.lawrencewu.holdfast.listen." + UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: output.uid,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: subs,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
            ]
            var dev = AudioObjectID(kAudioObjectUnknown)
            var err = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &dev)
            guard err == noErr else { throw HoldfastError("couldn't set up audio capture (Core Audio error \(err))") }
            aggregateID = dev
            let rate = SystemAudio.value(dev, kAudioDevicePropertyNominalSampleRate, Float64(0)).flatMap { $0 > 0 ? $0 : nil } ?? 48_000
            guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
                teardown()
                throw HoldfastError("unsupported sample rate \(rate)")
            }
            lock.lock(); skip = leave; format = fmt; lastIO = Date(); lock.unlock()

            var proc: AudioDeviceIOProcID?
            err = AudioDeviceCreateIOProcIDWithBlock(&proc, dev, io) { [weak self] _, input, _, _, _ in
                self?.receive(input)
            }
            guard err == noErr, let proc else {
                teardown()
                throw HoldfastError("couldn't start audio capture (Core Audio error \(err))")
            }
            procID = proc
            err = AudioDeviceStart(dev, proc)
            guard err == noErr else {
                teardown()
                throw HoldfastError("couldn't start audio capture (Core Audio error \(err))")
            }
        }

        /// One IO cycle: the streams after `skip` (the microphone, if any, then the tap), each
        /// averaged to mono, summed.
        private func receive(_ input: UnsafePointer<AudioBufferList>) {
            lock.lock()
            let leave = skip
            let fmt = format
            lastIO = Date()
            lock.unlock()
            guard let fmt else { return }
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            var frames = 0
            for (i, b) in list.enumerated() where i >= leave && b.mData != nil {
                frames = max(frames, Int(b.mDataByteSize) / (MemoryLayout<Float>.size * max(Int(b.mNumberChannels), 1)))
            }
            guard frames > 0, let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(frames)),
                  let dst = out.floatChannelData?[0] else { return }
            out.frameLength = AVAudioFrameCount(frames)
            dst.initialize(repeating: 0, count: frames)
            for (i, b) in list.enumerated() where i >= leave {
                guard let data = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let ch = max(Int(b.mNumberChannels), 1)
                let n = min(frames, Int(b.mDataByteSize) / (MemoryLayout<Float>.size * ch))
                for k in 0..<n {
                    var sum: Float = 0
                    for c in 0..<ch { sum += data[k * ch + c] }
                    dst[k] += sum / Float(ch)
                }
            }
            var pk: Float = 0
            for k in 0..<frames {
                dst[k] = min(max(dst[k], -1), 1)
                pk = max(pk, abs(dst[k]))
            }
            lock.lock(); loudest = max(loudest, pk); lock.unlock()
            onAudio(out)
        }

        /// Default-device changes and stalls rebuild the aggregate; an app's new audio processes join the tap.
        private func watch() {
            var selectors = [kAudioHardwarePropertyDefaultSystemOutputDevice, kAudioHardwarePropertyDefaultOutputDevice]
            if mic { selectors.append(kAudioHardwarePropertyDefaultInputDevice) }
            for sel in selectors {
                var a = SystemAudio.address(sel)
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.rebuild("the audio device changed") }
                if AudioObjectAddPropertyListenerBlock(SystemAudio.system, &a, control, block) == noErr { listeners.append((a, block)) }
            }
            let t = DispatchSource.makeTimerSource(queue: control)
            t.schedule(deadline: .now() + Self.refreshSeconds, repeating: Self.refreshSeconds)
            t.setEventHandler { [weak self] in
                guard let self else { return }
                self.refreshProcesses()
                self.lock.lock()
                let quiet = Date().timeIntervalSince(self.lastIO)
                self.lock.unlock()
                if quiet > Self.stallSeconds { self.rebuild("audio stopped arriving") }
            }
            t.resume()
            watchdog = t
        }

        /// On `control`: a fresh aggregate on the current default devices, the same tap.
        private func rebuild(_ why: String) {
            guard !stopped, Date().timeIntervalSince(lastRebuild) > 2 else { return }
            lastRebuild = Date()
            teardown()
            do {
                try build()
                let name = (try? SystemAudio.defaultDevice(kAudioHardwarePropertyDefaultSystemOutputDevice)).flatMap { SystemAudio.string($0.id, kAudioObjectPropertyName) } ?? "the new device"
                onEvent("\(why): listening again (\(name))")
            } catch {
                onEvent("\(why), and listening couldn't restart: \(error). Trying again shortly.")
            }
        }

        /// On `control`: for one app, adds audio processes it started since (and drops ended ones).
        private func refreshProcesses() {
            guard let target, !stopped else { return }
            let now = Set(target.current().map(\.object))
            guard !now.isEmpty, now != tapped else { return }
            let added = now.subtracting(tapped).count
            desc.processes = Array(now)
            var a = SystemAudio.address(kAudioTapPropertyDescription)
            var ref = desc
            let err = withUnsafeMutablePointer(to: &ref) {
                AudioObjectSetPropertyData(tapID, &a, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), $0)
            }
            if err == noErr {
                tapped = now
                if added > 0 { onEvent("\(target.name) started playing from another process: listening to it too") }
            }
        }

        /// Stops IO and removes the aggregate (the tap stays). On `control`.
        private func teardown() {
            guard aggregateID != kAudioObjectUnknown else { return }
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
            procID = nil
        }

        func stop() {
            control.sync {
                guard !stopped else { return }
                stopped = true
                watchdog?.cancel()
                watchdog = nil
                for (addr, block) in listeners {
                    var a = addr
                    AudioObjectRemovePropertyListenerBlock(SystemAudio.system, &a, control, block)
                }
                listeners = []
                teardown()
                if tapID != kAudioObjectUnknown {
                    AudioHardwareDestroyProcessTap(tapID)
                    tapID = AudioObjectID(kAudioObjectUnknown)
                }
            }
        }

        deinit { stop() }
    }
}
