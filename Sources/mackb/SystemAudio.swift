import AppKit
import AVFoundation
import CoreAudio
import Darwin
import Foundation

// MARK: - Audio from other apps (Core Audio process taps, macOS 14.2+)
//
// For `mackb listen --system` / `--app <name>`: a tap on what the Mac plays (everything, or one
// app's processes), put in a private aggregate device, optionally together with the default
// microphone so both sides of a call land in one transcript. The aggregate's clock is the output
// device's; the microphone gets drift compensation. Every input stream is mixed to mono and handed
// on as Float32 buffers at the aggregate's sample rate (the recognizer resamples to 16 kHz).
//
// Permission: macOS asks once for "System Audio Recording" (System Settings → Privacy & Security →
// Screen & System Audio Recording), for the app that runs mackb (from a terminal, the terminal).
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

    static func deviceUID(_ which: AudioObjectPropertySelector) throws -> String {
        guard let dev = value(system, which, AudioObjectID(kAudioObjectUnknown)), dev != kAudioObjectUnknown,
              let uid = string(dev, kAudioDevicePropertyDeviceUID) else {
            throw MacKBError(which == kAudioHardwarePropertyDefaultInputDevice ? "no microphone found" : "no audio output device found")
        }
        return uid
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

    /// Shows macOS's prompt for the app running mackb; true when allowed.
    static func requestAudioCapture() async -> Bool {
        typealias Request = @convention(c) (CFString, CFDictionary?, @escaping @convention(block) (Bool) -> Void) -> Void
        guard let tcc, let sym = dlsym(tcc, "TCCAccessRequest") else { return false }
        return await withCheckedContinuation { c in
            unsafeBitCast(sym, to: Request.self)("kTCCServiceAudioCapture" as CFString, nil) { c.resume(returning: $0) }
        }
    }

    static let captureDenied = MacKBError(
        "Recording system audio isn't allowed for the app running mackb. Allow it in System Settings → Privacy & Security → "
        + "Screen & System Audio Recording, under System Audio Recording Only (add Terminal, or whichever app you run mackb from), then try again.")

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

    /// The audio processes of an app, by name or bundle ID: "zoom", "teams", "chrome", "us.zoom.xos".
    /// Helpers count (a browser plays from its renderer or media processes): any process whose bundle
    /// ID starts with a matching app's bundle ID, or whose name or bundle ID contains the query.
    static func find(_ query: String) -> [AudioProcess] {
        let q = query.lowercased()
        let own = ProcessInfo.processInfo.processIdentifier
        var apps: [String] = []
        for a in NSWorkspace.shared.runningApplications {
            let name = (a.localizedName ?? "").lowercased()
            guard let bundle = a.bundleIdentifier?.lowercased(), name.contains(q) || bundle == q else { continue }
            apps.append(bundle)
        }
        return processes().filter { p in
            guard p.pid != own else { return false }
            let b = p.bundleID.lowercased()
            if p.name.lowercased().contains(q) || b.contains(q) { return true }
            return !b.isEmpty && apps.contains { b.hasPrefix($0) }
        }
    }

    // MARK: capture

    final class Capture {
        private var tapID = AudioObjectID(kAudioObjectUnknown)
        private var aggregateID = AudioObjectID(kAudioObjectUnknown)
        private var procID: AudioDeviceIOProcID?
        private let queue = DispatchQueue(label: "net.lawrencewu.mackb.listen.tap", qos: .userInitiated)
        private let lock = NSLock()
        private var loudest: Float = 0
        let sampleRate: Double

        /// The loudest sample so far: exactly 0 after several seconds usually means no permission.
        var peak: Float { lock.lock(); defer { lock.unlock() }; return loudest }

        /// `processes` nil taps everything the Mac plays (except mackb itself). `mute` silences the
        /// tapped audio on the speakers while it is captured.
        init(processes: [AudioObjectID]?, mic: Bool, mute: Bool, onAudio: @escaping (AVAudioPCMBuffer) -> Void) throws {
            let own = SystemAudio.processObject(pid: ProcessInfo.processInfo.processIdentifier)
            let desc = processes.map { CATapDescription(stereoMixdownOfProcesses: $0) }
                ?? CATapDescription(stereoGlobalTapButExcludeProcesses: own.map { [$0] } ?? [])
            desc.uuid = UUID()
            desc.name = "Holdfast listen"
            desc.isPrivate = true
            desc.muteBehavior = mute ? .mutedWhenTapped : .unmuted
            var tap = AudioObjectID(kAudioObjectUnknown)
            var err = AudioHardwareCreateProcessTap(desc, &tap)
            guard err == noErr else { throw MacKBError("couldn't tap the Mac's audio (Core Audio error \(err))") }
            tapID = tap

            do {
                let output = try SystemAudio.deviceUID(kAudioHardwarePropertyDefaultSystemOutputDevice)
                var subs: [[String: Any]] = [[kAudioSubDeviceUIDKey: output]]
                if mic {
                    subs.append([kAudioSubDeviceUIDKey: try SystemAudio.deviceUID(kAudioHardwarePropertyDefaultInputDevice),
                                 kAudioSubDeviceDriftCompensationKey: true])
                }
                let agg: [String: Any] = [
                    kAudioAggregateDeviceNameKey: "Holdfast listen",
                    kAudioAggregateDeviceUIDKey: "net.lawrencewu.mackb.listen." + UUID().uuidString,
                    kAudioAggregateDeviceMainSubDeviceKey: output,
                    kAudioAggregateDeviceIsPrivateKey: true,
                    kAudioAggregateDeviceIsStackedKey: false,
                    kAudioAggregateDeviceTapAutoStartKey: true,
                    kAudioAggregateDeviceSubDeviceListKey: subs,
                    kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
                ]
                var dev = AudioObjectID(kAudioObjectUnknown)
                err = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &dev)
                guard err == noErr else { throw MacKBError("couldn't set up audio capture (Core Audio error \(err))") }
                aggregateID = dev
            } catch {
                AudioHardwareDestroyProcessTap(tapID)
                throw error
            }
            sampleRate = SystemAudio.value(aggregateID, kAudioDevicePropertyNominalSampleRate, Float64(0)).flatMap { $0 > 0 ? $0 : nil } ?? 48_000
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
                stop()
                throw MacKBError("unsupported sample rate \(sampleRate)")
            }

            var proc: AudioDeviceIOProcID?
            err = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID, queue) { [weak self] _, input, _, _, _ in
                // Each input stream (the tap, the microphone) is averaged to mono and the streams summed.
                let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
                var frames = 0
                for b in list where b.mData != nil {
                    frames = max(frames, Int(b.mDataByteSize) / (MemoryLayout<Float>.size * max(Int(b.mNumberChannels), 1)))
                }
                guard frames > 0, let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
                      let dst = out.floatChannelData?[0] else { return }
                out.frameLength = AVAudioFrameCount(frames)
                dst.initialize(repeating: 0, count: frames)
                for b in list {
                    guard let data = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let ch = max(Int(b.mNumberChannels), 1)
                    let n = min(frames, Int(b.mDataByteSize) / (MemoryLayout<Float>.size * ch))
                    for i in 0..<n {
                        var s: Float = 0
                        for c in 0..<ch { s += data[i * ch + c] }
                        dst[i] += s / Float(ch)
                    }
                }
                var pk: Float = 0
                for i in 0..<frames {
                    dst[i] = min(max(dst[i], -1), 1)
                    pk = max(pk, abs(dst[i]))
                }
                if let self { self.lock.lock(); self.loudest = max(self.loudest, pk); self.lock.unlock() }
                onAudio(out)
            }
            guard err == noErr, let proc else {
                stop()
                throw MacKBError("couldn't start audio capture (Core Audio error \(err))")
            }
            procID = proc
            err = AudioDeviceStart(aggregateID, proc)
            guard err == noErr else {
                stop()
                throw MacKBError("couldn't start audio capture (Core Audio error \(err))")
            }
        }

        func stop() {
            if aggregateID != kAudioObjectUnknown {
                if let procID {
                    AudioDeviceStop(aggregateID, procID)
                    AudioDeviceDestroyIOProcID(aggregateID, procID)
                }
                AudioHardwareDestroyAggregateDevice(aggregateID)
                aggregateID = AudioObjectID(kAudioObjectUnknown)
            }
            procID = nil
            if tapID != kAudioObjectUnknown {
                AudioHardwareDestroyProcessTap(tapID)
                tapID = AudioObjectID(kAudioObjectUnknown)
            }
        }

        deinit { stop() }
    }
}
