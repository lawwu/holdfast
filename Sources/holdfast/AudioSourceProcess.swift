import Foundation

/// Owns the complete URL-source process group. Completion drains diagnostics and
/// preserves failures that happened before cleanup, including upstream failures.
final class AudioSourceProcess: @unchecked Sendable {
    private let process: Process
    private let fetcher: Process?
    private let source: String
    private let lock = NSLock()
    private let readers = DispatchGroup()
    private var launched: [Process] = []
    private var interrupted: Set<ObjectIdentifier> = []
    private var diagnostics: [ObjectIdentifier: String] = [:]
    private let echo: Bool

    init(_ process: Process, fetcher: Process? = nil, source: String, echo: Bool = false) {
        self.process = process; self.fetcher = fetcher; self.source = source; self.echo = echo
    }

    func start() throws -> FileHandle {
        let output = Pipe()
        process.standardOutput = output
        if let fetcher {
            let audio = Pipe()
            fetcher.standardOutput = audio
            process.standardInput = audio
        }
        do {
            for child in [fetcher, process].compactMap({ $0 }) {
                let errors = Pipe()
                child.standardError = errors
                try child.run()
                lock.withLock { launched.append(child) }
                readers.enter()
                DispatchQueue.global().async { [self] in
                    defer { readers.leave() }
                    while let data = try? errors.fileHandleForReading.read(upToCount: 4096), !data.isEmpty {
                        lock.withLock {
                            let id = ObjectIdentifier(child)
                            diagnostics[id] = String(((diagnostics[id] ?? "") + String(decoding: data, as: UTF8.self)).suffix(1500))
                        }
                        if echo { FileHandle.standardError.write(data) }
                    }
                }
            }
        } catch {
            stop()
            for child in lock.withLock({ launched }) { child.waitUntilExit() }
            readers.wait()
            throw error
        }
        return output.fileHandleForReading
    }

    func stop() {
        lock.withLock {
            for child in launched where child.isRunning {
                interrupted.insert(ObjectIdentifier(child))
                child.terminate()
            }
        }
    }

    /// Called on EOF, or after stop. An ended decoder must not leave its fetcher
    /// running forever. Only processes actually terminated by us are suppressed.
    func finish() -> String? {
        process.waitUntilExit()
        lock.withLock {
            if let fetcher, fetcher.isRunning {
                interrupted.insert(ObjectIdentifier(fetcher))
                fetcher.terminate()
            }
        }
        fetcher?.waitUntilExit()
        readers.wait()
        return lock.withLock {
            for child in [fetcher, process].compactMap({ $0 }) {
                guard !interrupted.contains(ObjectIdentifier(child)), child.terminationStatus != 0 else { continue }
                let name = child === fetcher ? "yt-dlp" : "ffmpeg"
                let text = diagnostics[ObjectIdentifier(child)] ?? ""
                let lines = text.split(separator: "\n")
                let detail = lines.last(where: { $0.contains("ERROR") }) ?? lines.last
                return "\(name) couldn't read \(source): " + (detail.map(String.init) ?? "exit status \(child.terminationStatus)")
            }
            return nil
        }
    }
}
