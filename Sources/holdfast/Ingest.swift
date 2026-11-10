import AVFoundation
import FluidAudio
import Foundation
import PDFKit
import Vision

// MARK: - Documents

let docExtensions: Set<String> = ["md", "markdown", "txt", "docx", "doc", "rtf", "pdf", "html", "htm"]
let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "mp4", "mov", "m4v", "webm", "ogg", "opus"]

/// Plain text from a document, using only what ships with macOS:
/// textutil for Word/RTF/HTML, PDFKit for PDF.
func extractText(_ url: URL) throws -> String {
    switch url.pathExtension.lowercased() {
    case "md", "markdown", "txt":
        return try Formats.readText(url)
    case let e where imageExtensions.contains(e):
        return try ocrImage(url)
    case let e where Formats.readable.contains(e):
        return try Formats.text(url)
    case "pdf":
        guard let doc = PDFDocument(url: url) else { throw HoldfastError("can't open PDF \(url.lastPathComponent)") }
        // Page by page: a page with no text layer (a scan, a photo of a form) is read
        // with on-device OCR, so a PDF that mixes typed and scanned pages reads in full.
        var pages: [String] = []
        var ocrPages = 0
        for i in 0..<doc.pageCount {
            autoreleasepool {
                let t = doc.page(at: i)?.string ?? ""
                if t.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20 { pages.append(t); return }
                // Scanned pages are read with OCR, up to a limit (each is rendered as an image).
                guard ocrPages < maxOCRPages else { return }
                ocrPages += 1
                pages.append(ocrPDFPage(doc, i))
            }
        }
        return pages.joined(separator: "\n\n")
    default:
        return try run("/usr/bin/textutil", ["-convert", "txt", "-stdout", url.path])
    }
}

/// Apple Vision OCR, page by page, at ~2x resolution. Built into macOS; nothing leaves the Mac.
func ocrPDF(_ doc: PDFDocument) -> String {
    (0..<doc.pageCount).map { ocrPDFPage(doc, $0) }.joined(separator: "\n\n")
}

/// Scanned pages read with OCR per PDF, and the longest side a page is rendered at (pixels).
let maxOCRPages = 300
let maxOCRSide: CGFloat = 2_400

func ocrPDFPage(_ doc: PDFDocument, _ i: Int) -> String {
    guard let page = doc.page(at: i) else { return "" }
    let bounds = page.bounds(for: .mediaBox)
    // About 2x a letter page; huge pages are scaled down so one page can't take gigabytes.
    let scale = min(2, maxOCRSide / max(bounds.width, bounds.height, 1))
    let img = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
    guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = true
    try? VNImageRequestHandler(cgImage: cg).perform([req])
    return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
}

/// Word bullets and tabs come through textutil as odd characters; make them Markdown.
func tidy(_ text: String) -> String {
    text.replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\u{2028}", with: "\n")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> String in
            var l = line.trimmingCharacters(in: .whitespaces)
            for b in ["\t•\t", "•\t", "•", "\t◦\t", "◦", "▪", "\u{F0B7}"] where l.hasPrefix(b) {
                l = "- " + l.dropFirst(b.count).trimmingCharacters(in: .whitespaces)
                break
            }
            // Plain text loses Word heading styles. A short standalone line ending in "?"
            // is a form prompt (the case report form is 16 of them): make it a heading,
            // so chunks and citations land on the question being answered.
            if l.hasSuffix("?"), l.count < 200, !l.hasPrefix("- "), !l.hasPrefix("\"") {
                l = "## " + l
            }
            return l
        }
        .joined(separator: "\n")
        .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Import one document as a vault note. Markdown keeps its own headings; other
/// formats become a note whose first heading is the file name.
@discardableResult
func ingestDocument(_ url: URL, root: URL?, tags: [String]) throws -> Note {
    let raw = try extractText(url)
    let isMD = ["md", "markdown"].contains(url.pathExtension.lowercased())
    var body = isMD ? raw : tidy(raw)
    var title = url.deletingPathExtension().lastPathComponent
    var meta: [String: String] = [:]
    if isMD, raw.hasPrefix("---\n"), let n = try? Note.read(url) {  // keep source frontmatter
        meta = n.meta
        body = n.body
    }
    if isMD, let h1 = body.split(separator: "\n").first(where: { $0.hasPrefix("# ") }) {
        title = String(h1.dropFirst(2))
    } else if !isMD {
        // A short first line ("Case Report — D.M. — Session 1") is a better title than the file name.
        if let first = body.split(separator: "\n").first.map(String.init), first.count >= 6, first.count <= 90,
           !first.hasPrefix("## "), !first.hasSuffix(".") {
            title = first
            body = String(body.dropFirst(first.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        body = "# \(title)\n\n" + body
    }
    // Folder path under the import root becomes the note's folder and a topic tag.
    var rel = url.lastPathComponent
    var folderTags: [String] = []
    if let root, url.path.hasPrefix(root.path + "/") {
        rel = String(url.path.dropFirst(root.path.count + 1))
        folderTags = rel.split(separator: "/").dropLast().map { slugify(String($0)) }
    }
    let relNoExt = (rel as NSString).deletingPathExtension
    let dest = Config.sourcesDir.appendingPathComponent(
        (relNoExt.split(separator: "/").map { slugify(String($0)) }.joined(separator: "/")) + ".md")
    meta["title"] = title
    meta["source"] = url.path
    meta["kind"] = "document"
    meta["format"] = url.pathExtension.lowercased()
    let allTags = Array(Set(tags + folderTags)).sorted()
    if !allTags.isEmpty { meta["tags"] = allTags.joined(separator: ", ") }
    meta.merge(caseMetadata(title: title, body: body)) { old, _ in old }
    let note = Note(path: dest, meta: meta, body: "\n" + body + "\n")
    try note.write()
    return note
}

/// Case-report metadata from the ACBC form header ("Date: … Session: N") and an
/// initials-style counselee id in the title ("D.M."). Becomes frontmatter, so
/// retrieval can filter by session and label every passage with it.
func caseMetadata(title: String, body: String) -> [String: String] {
    func first(_ pattern: String, _ text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
    let head = String(body.prefix(600))
    guard let session = first(#"Session:\s*(\d{1,3})"#, head) ?? first(#"Session\s+(\d{1,3})\b"#, title) else { return [:] }
    var m = ["session": session, "doc_type": "case-report"]
    if let d = first(#"Date:\s*(\d{4}-\d{2}-\d{2})"#, head) { m["date"] = d }
    if let kind = first(#"Session:\s*\d{1,3}\s*\(([^)]{3,60})\)"#, head) { m["session_kind"] = kind }
    if let c = first(#"\b((?:[A-Z]\.){2,3})"#, title) ?? first(#"\b((?:[A-Z]\.){2,3})"#, head) { m["case"] = c }
    return m
}

/// Walk a folder. When a lesson exists as both .docx and .pdf (common in a
/// supervisor's working folder), keep one: docx > doc > md > pdf.
func ingestFolder(_ root: URL, tags: [String]) throws -> (ok: Int, skipped: Int, failed: [String]) {
    let rank: [String: Int] = ["md": 0, "markdown": 0, "docx": 1, "doc": 2, "rtf": 3, "txt": 3, "html": 4, "htm": 4, "pdf": 5]
    var best: [String: URL] = [:]
    var skipped = 0
    let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])!
    for case let u as URL in e {
        let ext = u.pathExtension.lowercased()
        guard docExtensions.contains(ext), !u.lastPathComponent.hasPrefix("~$") else { continue }
        let key = u.deletingPathExtension().path.lowercased()
        if let cur = best[key] {
            skipped += 1
            if rank[ext, default: 9] < rank[cur.pathExtension.lowercased(), default: 9] { best[key] = u }
        } else {
            best[key] = u
        }
    }
    var ok = 0
    var failed: [String] = []
    for u in best.values.sorted(by: { $0.path < $1.path }) {
        do {
            let n = try ingestDocument(u, root: root, tags: tags)
            if n.body.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 { failed.append("\(u.lastPathComponent): no text (scanned?)") }
            ok += 1
        } catch {
            failed.append("\(u.lastPathComponent): \(error)")
        }
    }
    return (ok, skipped, failed)
}

// MARK: - Audio (FluidAudio Parakeet v3 or v2 per Settings, in-process on the Neural Engine)

func transcribeAudio(_ url: URL) async throws -> (segments: [Segment], duration: Double, seconds: Double) {
    let wav = Config.mediaDir.appendingPathComponent(UUID().uuidString + ".wav")
    // ffmpeg normalises any container (mp4, webm, m4a) to 16 kHz mono for Parakeet.
    guard let ffmpeg = findTool("ffmpeg") else {
        throw HoldfastError("Recordings need ffmpeg to read audio. Install it with Homebrew (brew install ffmpeg), then try again.")
    }
    _ = try run(ffmpeg, ["-nostdin", "-loglevel", "error", "-y", "-i", url.path, "-ac", "1", "-ar", "16000", wav.path])
    defer { try? FileManager.default.removeItem(at: wav) }

    let choice = Prefs.transcription
    log("loading \(choice.name) (first run downloads the CoreML model)…")
    let models = try await AsrModels.downloadAndLoad(version: choice == .parakeetV2 ? .v2 : .v3)
    let asr = AsrManager(config: .default)
    try await asr.loadModels(models)
    var state = TdtDecoderState.make()
    let t0 = Date()  // time transcription only, not the one-time model download/compile
    let result = try await asr.transcribe(wav, decoderState: &state)
    let elapsed = Date().timeIntervalSince(t0)
    return (segmentsFromTokens(result), result.duration, elapsed)
}

/// Parakeet gives sub-word tokens with times; group them into readable lines,
/// breaking on a pause, end of sentence, or a maximum length.
func segmentsFromTokens(_ r: ASRResult) -> [Segment] {
    guard let toks = r.tokenTimings, !toks.isEmpty else { return [Segment(start: 0, text: r.text)] }
    return segments(fromTokens: toks)
}

/// The grouping itself, shared with live transcription (Listen.swift). A line's boundary depends
/// only on the tokens before it, so the lines of a prefix never change as more tokens arrive.
func segments(fromTokens toks: [TokenTiming]) -> [Segment] { segmentRanges(toks[...]).map(\.segment) }

/// The lines of a run of tokens, each with the index just past its last token, so a caller can
/// start the next pass at a line boundary instead of from the beginning.
func segmentRanges(_ toks: ArraySlice<TokenTiming>) -> [(segment: Segment, end: Int)] {
    guard let first = toks.first else { return [] }
    var out: [(segment: Segment, end: Int)] = []
    var cur = ""
    var start = first.startTime
    var lastEnd = first.startTime
    func flush(at end: Int) {
        let t = cur.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { out.append((Segment(start: start, text: t), end)) }
        cur = ""
    }
    for i in toks.indices {
        let tk = toks[i]
        let piece = tk.token.replacingOccurrences(of: "▁", with: " ")
        let gap = tk.startTime - lastEnd
        let long = tk.startTime - start > Config.segmentMaxSeconds
        let sentenceEnd = cur.hasSuffix(".") || cur.hasSuffix("?") || cur.hasSuffix("!")
        if !cur.isEmpty, piece.hasPrefix(" "), gap > Config.segmentPause || long || (sentenceEnd && tk.startTime - start > 6) {
            flush(at: i)
            start = tk.startTime
        }
        if cur.isEmpty { start = tk.startTime }
        cur += piece
        lastEnd = tk.endTime
    }
    flush(at: toks.endIndex)
    return out
}

func ingestAudio(_ url: URL, title: String?, tags: [String]) async throws -> Note {
    let (segs, dur, secs) = try await transcribeAudio(url)
    log(String(format: "transcribed %@ of audio in %.1fs (%.0fx real time)", formatTime(dur), secs, dur / max(secs, 0.01)))
    var extra: [String: String] = ["transcriber": "parakeet-tdt-0.6b-v3 (FluidAudio)"]
    if !tags.isEmpty { extra["tags"] = tags.joined(separator: ", ") }
    return try transcriptNote(title: title ?? url.deletingPathExtension().lastPathComponent,
                              source: url.path, kind: "recording", duration: dur, segments: segs, extra: extra)
}

// MARK: - YouTube / URLs (captions first, transcription only if there are none)

/// A command-line tool from the usual install places (the app doesn't get the shell's PATH).
func findTool(_ name: String) -> String? {
    let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "\(NSHomeDirectory())/.local/bin", "\(NSHomeDirectory())/miniconda3/bin", "/usr/bin"]
    return dirs.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
}

func ytdlp() -> String {
    findTool("yt-dlp") ?? "yt-dlp"
}

func ingestURL(_ url: String, tags: [String]) async throws -> Note {
    guard findTool("yt-dlp") != nil else {
        throw HoldfastError("Links need yt-dlp to fetch captions or audio. Install it with Homebrew (brew install yt-dlp), then try again.")
    }
    let work = Config.mediaDir.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: work) }
    let info = try run(ytdlp(), ["--no-playlist", "--skip-download", "--print", "%(title)s\t%(duration)s", url])
    let parts = info.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
    let title = parts.first ?? url
    var extra: [String: String] = [:]
    if !tags.isEmpty { extra["tags"] = tags.joined(separator: ", ") }

    _ = try? run(ytdlp(), ["--no-playlist", "--skip-download", "--write-subs", "--write-auto-subs",
                           "--sub-langs", "en.*,en", "--sub-format", "vtt", "-o", work.appendingPathComponent("v").path, url])
    let vtts = (try? FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "vtt" } ?? []
    // Prefer human captions (no "-orig"/auto marker is reliable, so take the shortest name = plain "en").
    if let vtt = vtts.sorted(by: { $0.lastPathComponent.count < $1.lastPathComponent.count }).first {
        let segs = parseVTT(try String(contentsOf: vtt, encoding: .utf8))
        if !segs.isEmpty {
            log("used the video's captions (\(segs.count) segments); no transcription needed")
            extra["transcriber"] = "youtube captions"
            return try transcriptNote(title: title, source: url, kind: "video", duration: Double(parts.last ?? "") ?? segs.last!.start,
                                      segments: segs, extra: extra)
        }
    }
    log("no captions; downloading audio and transcribing")
    _ = try run(ytdlp(), ["--no-playlist", "-f", "bestaudio", "-x", "--audio-format", "m4a",
                          "-o", work.appendingPathComponent("a.%(ext)s").path, url])
    let audio = work.appendingPathComponent("a.m4a")
    let (segs, dur, secs) = try await transcribeAudio(audio)
    log(String(format: "transcribed %@ in %.1fs", formatTime(dur), secs))
    extra["transcriber"] = "parakeet-tdt-0.6b-v3 (FluidAudio)"
    return try transcriptNote(title: title, source: url, kind: "video", duration: dur, segments: segs, extra: extra)
}

/// WebVTT → segments. YouTube auto-captions repeat each line as it scrolls, so
/// drop lines already seen and merge cues into ~segmentMaxSeconds lines.
func parseVTT(_ s: String) -> [Segment] {
    var cues: [Segment] = []
    var seen = Set<String>()
    var curStart: Double?
    for block in s.components(separatedBy: "\n\n") {
        let lines = block.split(separator: "\n").map(String.init)
        guard let tl = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
        let startStr = lines[tl].components(separatedBy: " --> ")[0].trimmingCharacters(in: .whitespaces)
        let hms = startStr.split(separator: ".")[0]
        let p = hms.split(separator: ":").compactMap { Double($0) }
        let t = p.count == 3 ? p[0] * 3600 + p[1] * 60 + p[2] : (p.count == 2 ? p[0] * 60 + p[1] : 0)
        curStart = t
        for l in lines[(tl + 1)...] {
            let clean = l.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            if clean.isEmpty || seen.contains(clean) { continue }
            seen.insert(clean)
            cues.append(Segment(start: curStart ?? 0, text: clean))
        }
    }
    var out: [Segment] = []
    for c in cues {
        if var last = out.last, c.start - last.start < Config.segmentMaxSeconds {
            last.text += " " + c.text
            out[out.count - 1] = last
        } else {
            out.append(c)
        }
    }
    return out
}

// MARK: - helpers

struct HoldfastError: Error, CustomStringConvertible {
    let description: String
    init(_ s: String) { description = s }
}

@discardableResult
func run(_ exe: String, _ args: [String]) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe.hasPrefix("/") ? exe : "/usr/bin/env")
    p.arguments = exe.hasPrefix("/") ? args : [exe] + args
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    try p.run()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    let edata = err.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
        throw HoldfastError("\((exe as NSString).lastPathComponent) failed: \(String(data: edata, encoding: .utf8) ?? "")")
    }
    return String(decoding: data, as: UTF8.self)
}
