import Foundation

func command(_ text: String) -> Process {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/sh"); p.arguments = ["-c", text]; return p
}
func require(_ value: Bool, _ message: String) throws { if !value { throw NSError(domain: message, code: 1) } }
@main struct SourceTests {
    static func main() throws {
        let success = AudioSourceProcess(command("printf audio"), source: "fixture")
        let bytes = try success.start().readToEnd()
        try require(bytes == Data("audio".utf8) && success.finish() == nil, "natural EOF")
        let failed = AudioSourceProcess(command("printf partial; echo decoder-failed >&2; exit 7"), source: "fixture")
        let partial = try failed.start().readToEnd()
        let failure = failed.finish()
        failed.stop()
        try require(partial == Data("partial".utf8) && failure?.contains("decoder-failed") == true, "lost partial audio or failure")
        try require(failed.finish() == failure, "cleanup erased failure")
        let stopped = AudioSourceProcess(command("exec sleep 30"), source: "fixture")
        _ = try stopped.start(); stopped.stop()
        try require(stopped.finish() == nil, "intentional stop reported failure")
        let upstream = command("echo ERROR-upstream >&2; exit 9")
        let pipeline = AudioSourceProcess(command("cat >/dev/null"), fetcher: upstream, source: "fixture")
        _ = try pipeline.start().readToEnd()
        try require(pipeline.finish()?.contains("ERROR-upstream") == true, "upstream failure lost")
        let missing = Process(); missing.executableURL = URL(fileURLWithPath: "/does-not-exist/decoder")
        let started = command("exec sleep 30")
        do { _ = try AudioSourceProcess(missing, fetcher: started, source: "fixture").start(); throw NSError(domain: "startup unexpectedly worked", code: 1) }
        catch { try require(!started.isRunning, "partial startup leaked process") }
        print("PASS source EOF, partial audio, failure preservation, stop, upstream failure and partial startup cleanup")
    }
}
