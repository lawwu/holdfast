import Foundation

// MARK: - More file types
//
// Readers for formats beyond the documents, images and recordings Ingest.swift
// handles, using only what ships with macOS: `unzip` and `ditto` for the
// zip-based formats (xlsx, pptx, epub, Day One), XMLParser, and plain parsing
// for mail, calendars and contacts. Containers (zip, mbox, Evernote .enex,
// an .eml's attachments) are opened into their files by `Expand` before
// anything is filed or imported.

enum Formats {
    /// Converted by macOS's textutil, like .docx.
    static let textutil: Set<String> = ["odt", "webarchive", "wordml"]
    /// Read as text as they are.
    static let plain: Set<String> = ["csv", "tsv", "json", "xml", "yaml", "yml", "log", "org", "tex", "opml"]
    static let structured: Set<String> = ["xlsx", "pptx", "epub", "eml", "ics", "vcf"]
    /// Opened into their files first.
    static let containers: Set<String> = ["zip", "mbox", "enex"]
    static var readable: Set<String> { textutil.union(plain).union(structured) }

    /// Files larger than this aren't read for text (a filing reads 12k characters anyway).
    static let maxFileBytes = 256 * 1024 * 1024
    /// Archives that would unpack to more than this are refused (zip bombs).
    static let maxUnzippedBytes: Int64 = 2 * 1024 * 1024 * 1024
    /// Files an archive may hold.
    static let maxZipEntries = 20_000
    /// Spreadsheet columns read per row (Excel's own limit is 16,384).
    static let maxColumns = 1_024

    /// Text in UTF-8, UTF-16 (with a byte-order mark) or, failing those, Windows-1252.
    static func readText(_ url: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let n = attrs[.size] as? Int, n > maxFileBytes { throw HoldfastError("\(url.lastPathComponent) is too large to read (\(n / 1_048_576) MB)") }
        return decodeText(try Data(contentsOf: url))
    }

    static func decodeText(_ d: Data) -> String {
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: d.dropFirst(3), as: UTF8.self) }
        if d.starts(with: [0xFF, 0xFE]) { return String(data: d, encoding: .utf16LittleEndian).map { String($0.drop { $0 == "\u{FEFF}" }) } ?? "" }
        if d.starts(with: [0xFE, 0xFF]) { return String(data: d, encoding: .utf16BigEndian).map { String($0.drop { $0 == "\u{FEFF}" }) } ?? "" }
        if let s = String(data: d, encoding: .utf8) { return s }
        return String(data: d, encoding: .windowsCP1252) ?? String(decoding: d, as: UTF8.self)
    }

    static func text(_ url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if let n = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, n > maxFileBytes {
            throw HoldfastError("\(url.lastPathComponent) is too large to read (\(n / 1_048_576) MB)")
        }
        switch ext {
        case "xlsx":
            return try xlsxSheets(url).map { s in "## Sheet: \(s.name)\n\n" + s.rows.map(csvLine).joined(separator: "\n") }
                .joined(separator: "\n\n")
        case "pptx": return try pptx(url)
        case "epub": return try epub(url)
        case "eml": return mailText(Mail.parse(try Data(contentsOf: url)))
        case "ics": return ics(try readText(url))
        case "vcf": return vcf(try readText(url))
        case "json":
            let data = try Data(contentsOf: url)
            if data.count < 5_000_000, let obj = try? JSONSerialization.jsonObject(with: data),
               let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                return String(decoding: pretty, as: UTF8.self)
            }
            return String(decoding: data, as: UTF8.self)
        case let e where textutil.contains(e):
            return tidy(try run("/usr/bin/textutil", ["-convert", "txt", "-stdout", url.path]))
        default:
            return try readText(url)
        }
    }

    // MARK: zip

    /// A zip archive unpacked into a temporary folder: ditto keeps non-ASCII names and
    /// strips "../" and absolute entry paths; the folder is removed when this goes away.
    final class ZipDir {
        let root: URL
        init(_ zip: URL) throws {
            // zipinfo's last line: "N files, X bytes uncompressed, …": refuse archives that unpack huge.
            if let info = try? run("/usr/bin/zipinfo", ["-t", zip.path]) {
                if let m = info.range(of: #"([0-9]+) bytes uncompressed"#, options: .regularExpression),
                   let n = Int64(info[m].split(separator: " ").first ?? ""), n > Formats.maxUnzippedBytes {
                    throw HoldfastError("\(zip.lastPathComponent) would unpack to \(n / 1_073_741_824) GB; not opened")
                }
                if let m = info.range(of: #"^([0-9]+) files"#, options: .regularExpression),
                   let n = Int(info[m].split(separator: " ").first ?? ""), n > Formats.maxZipEntries {
                    throw HoldfastError("\(zip.lastPathComponent) holds \(n) files; not opened (the limit is \(Formats.maxZipEntries))")
                }
            }
            root = FileManager.default.temporaryDirectory.appendingPathComponent("holdfast-zip-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            _ = try run("/usr/bin/ditto", ["-x", "-k", "--", zip.path, root.path])
        }
        deinit { try? FileManager.default.removeItem(at: root) }

        private var base: String { root.resolvingSymlinksInPath().standardizedFileURL.path + "/" }

        /// Entry paths, relative, regular files only (no symlinks).
        lazy var entries: [String] = {
            let items = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])?
                .compactMap { $0 as? URL } ?? []
            return items.compactMap { u -> String? in
                let v = try? u.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard v?.isRegularFile == true, v?.isSymbolicLink != true else { return nil }
                let p = u.resolvingSymlinksInPath().standardizedFileURL.path
                return p.hasPrefix(base) ? String(p.dropFirst(base.count)) : nil
            }.sorted()
        }()

        /// An entry's bytes; "a/../b" style paths are resolved but must stay inside the archive.
        func read(_ entry: String) throws -> Data {
            let u = root.appendingPathComponent(entry).resolvingSymlinksInPath().standardizedFileURL
            guard u.path.hasPrefix(base) else { throw HoldfastError("archive entry outside the archive: \(entry)") }
            return try Data(contentsOf: u)
        }

        func contains(_ entry: String) -> Bool { entries.contains(entry) }
    }

    /// "OEBPS/../Text/ch1.xhtml" → "Text/ch1.xhtml" (no leading "..").
    static func normalize(_ path: String) -> String {
        var out: [Substring] = []
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { _ = out.popLast() } else { out.append(part) }
        }
        return out.joined(separator: "/")
    }

    // MARK: spreadsheets (xlsx)

    struct Sheet { var name: String; var rows: [[String]] }

    static func xlsxSheets(_ url: URL) throws -> [Sheet] {
        let z = try ZipDir(url)
        let entries = z.entries
        var shared: [String] = []
        if z.contains("xl/sharedStrings.xml") {
            let x = XMLCollector()
            x.parse(try z.read("xl/sharedStrings.xml"))
            shared = x.groups(of: "si", text: "t")
        }
        // Sheet names in workbook order, each tied to its file through the workbook's relationships
        // (files are numbered by creation, so a reordered workbook doesn't match by number).
        var named: [(name: String, file: String)] = []
        if z.contains("xl/workbook.xml") {
            let x = XMLCollector()
            x.parse(try z.read("xl/workbook.xml"))
            let names = x.attributes(of: "sheet", "name"), rids = x.attributes(of: "sheet", "r:id")
            var targets: [String: String] = [:]
            if z.contains("xl/_rels/workbook.xml.rels") {
                let r = XMLCollector()
                r.parse(try z.read("xl/_rels/workbook.xml.rels"))
                targets = Dictionary(zip(r.attributes(of: "Relationship", "Id"), r.attributes(of: "Relationship", "Target")), uniquingKeysWith: { a, _ in a })
            }
            if names.count == rids.count {
                for (n, id) in zip(names, rids) {
                    guard let t = targets[id] else { continue }
                    named.append((n, normalize(t.hasPrefix("/") ? String(t.dropFirst()) : "xl/" + t)))
                }
            }
        }
        if !named.isEmpty, named.allSatisfy({ z.contains($0.file) }) {
            return try named.map { s in
                let p = SheetParser(shared: shared)
                p.parse(try z.read(s.file))
                return Sheet(name: s.name, rows: p.rows)
            }
        }
        let names = named.map(\.name)
        let sheets = entries.filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted { (Int($0.filter(\.isNumber)) ?? 0) < (Int($1.filter(\.isNumber)) ?? 0) }
        return try sheets.enumerated().map { i, e in
            let p = SheetParser(shared: shared)
            p.parse(try z.read(e))
            return Sheet(name: i < names.count ? names[i] : "Sheet\(i + 1)", rows: p.rows)
        }
    }

    static func csvLine(_ row: [String]) -> String {
        row.map { c in c.contains(where: { ",\"\n\r".contains($0) || $0 == "\r\n" }) ? "\"" + c.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : c }
            .joined(separator: ",")
    }

    // MARK: slides (pptx)

    static func pptx(_ url: URL) throws -> String {
        let z = try ZipDir(url)
        let slides = z.entries.filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted { (Int($0.filter(\.isNumber)) ?? 0) < (Int($1.filter(\.isNumber)) ?? 0) }
        return try slides.enumerated().map { i, e in
            let x = XMLCollector()
            x.parse(try z.read(e))
            return "## Slide \(i + 1)\n\n" + x.groups(of: "a:p", text: "a:t").filter { !$0.isEmpty }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    // MARK: ebooks (epub)

    static func epub(_ url: URL) throws -> String {
        let z = try ZipDir(url)
        let entries = z.entries
        var order: [String] = []
        if z.contains("META-INF/container.xml") {
            let c = XMLCollector()
            c.parse(try z.read("META-INF/container.xml"))
            if let opf = c.attributes(of: "rootfile", "full-path").first, z.contains(opf) {
                let o = XMLCollector()
                o.parse(try z.read(opf))
                let base = (opf as NSString).deletingLastPathComponent
                let hrefs = Dictionary(zip(o.attributes(of: "item", "id"), o.attributes(of: "item", "href")), uniquingKeysWith: { a, _ in a })
                order = o.attributes(of: "itemref", "idref").compactMap { hrefs[$0] }
                    .map { base.isEmpty ? $0 : base + "/" + $0 }
                    .map { normalize($0.removingPercentEncoding ?? $0) }
            }
        }
        if order.isEmpty { order = entries.filter { $0.hasSuffix(".xhtml") || $0.hasSuffix(".html") || $0.hasSuffix(".htm") }.sorted() }
        return try order.filter { entries.contains($0) }
            .map { htmlToText(decodeText(try z.read($0))) }
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func htmlToText(_ html: String) -> String {
        var s = stripBlocks(html, ["script", "style", "head"])
        s = s.replacingOccurrences(of: #"(?i)<h([1-6])[^>]*>"#, with: "\n\n## ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<li[^>]*>"#, with: "\n- ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)<br\s*/?>|</(p|div|h[1-6]|tr|li|blockquote)>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)</t[dh]>"#, with: " | ", options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes <tag …>…</tag> blocks in one pass; an unclosed one loses just its opening tag.
    /// ("<header>" isn't "<head>": the name must end at a space, ">" or "/".)
    static func stripBlocks(_ html: String, _ tags: [String]) -> String {
        var out = ""
        var i = html.startIndex
        let lower = html.lowercased()
        guard lower.count == html.count else { return html }  // case mapping changed length: leave it
        func at(_ j: String.Index) -> String.Index { lower.index(lower.startIndex, offsetBy: html.distance(from: html.startIndex, to: j)) }
        while let lt = html[i...].firstIndex(of: "<") {
            out += html[i..<lt]
            let li = at(lt)
            var matched: String?
            for t in tags where lower[li...].hasPrefix("<" + t) {
                let after = lower.index(li, offsetBy: t.count + 1, limitedBy: lower.endIndex) ?? lower.endIndex
                if after == lower.endIndex || " \t\n\r>/".contains(lower[after]) { matched = t; break }
            }
            guard let t = matched else { out += "<"; i = html.index(after: lt); continue }
            let openEnd = html[lt...].firstIndex(of: ">").map { html.index(after: $0) } ?? html.endIndex
            if let close = lower.range(of: "</" + t, range: at(openEnd)..<lower.endIndex) {
                let closeOff = lower.distance(from: lower.startIndex, to: close.upperBound)
                let closeIdx = html.index(html.startIndex, offsetBy: closeOff)
                i = html[closeIdx...].firstIndex(of: ">").map { html.index(after: $0) } ?? html.endIndex
            } else {
                i = openEnd
            }
        }
        out += html[i...]
        return out
    }

    static func decodeEntities(_ s: String) -> String {
        var s = s
        for (k, v) in ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&mdash;": "—", "&ndash;": "–",
                       "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“", "&hellip;": "…"] {
            s = s.replacingOccurrences(of: k, with: v)
        }
        let re = try! NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            let ns = s as NSString
            let hex = ns.substring(with: m.range(at: 1)) == "x"
            if let n = UInt32(ns.substring(with: m.range(at: 2)), radix: hex ? 16 : 10), let u = Unicode.Scalar(n),
               let r = Range(m.range, in: s) {
                s.replaceSubrange(r, with: String(Character(u)))
            }
        }
        return s.replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: mail (eml)

    static func mailText(_ m: Mail) -> String {
        var out = ["From", "To", "Cc", "Date", "Subject"].compactMap { k in m.header(k).map { "\(k): \($0)" } }.joined(separator: "\n")
        out += "\n\n" + m.text
        if !m.attachments.isEmpty { out += "\n\nAttachments: " + m.attachments.map(\.name).joined(separator: ", ") }
        return out
    }

    // MARK: calendars and contacts

    /// Unfolded "KEY;PARAMS:value" lines of an iCalendar or vCard file.
    static func icalLines(_ text: String) -> [(key: String, value: String)] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            if (raw.hasPrefix(" ") || raw.hasPrefix("\t")), !lines.isEmpty { lines[lines.count - 1] += raw.dropFirst() } else { lines.append(raw) }
        }
        return lines.compactMap { l in
            guard let c = l.firstIndex(of: ":") else { return nil }
            let params = l[..<c].split(separator: ";").map(String.init)
            let key = params.first?.uppercased() ?? ""
            var raw = String(l[l.index(after: c)...])
            if params.contains(where: { $0.uppercased().contains("QUOTED-PRINTABLE") }) {
                let cs = params.first { $0.uppercased().hasPrefix("CHARSET=") }.map { String($0.dropFirst(8)) } ?? "utf-8"
                raw = Mail.decodeCharset(Mail.quotedPrintable(raw), cs)
            }
            let v = raw.replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\N", with: " ")
                .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
            return (key, v)
        }
    }

    static func icalDate(_ v: String) -> String {
        let d = v.filter { $0.isNumber || $0 == "T" }
        guard d.count >= 8 else { return v }
        var out = "\(d.prefix(4))-\(d.dropFirst(4).prefix(2))-\(d.dropFirst(6).prefix(2))"
        if d.count >= 13, let t = d.firstIndex(of: "T") {
            let hm = d[d.index(after: t)...]
            out += " \(hm.prefix(2)):\(hm.dropFirst(2).prefix(2))" + (v.hasSuffix("Z") ? " UTC" : "")
        }
        return out
    }

    static func ics(_ text: String) -> String {
        var out: [String] = []
        var cur: [String: String]?
        for (k, v) in icalLines(text) {
            if k == "BEGIN", v == "VEVENT" || v == "VTODO" { cur = ["_kind": v] }
            else if k == "END", v == "VEVENT" || v == "VTODO", let c = cur {
                var line = "- " + [c["DTSTART"] ?? c["DUE"]].compactMap { $0.map(icalDate) }.joined()
                if let e = c["DTEND"] { line += " to " + icalDate(e) }
                line += " — " + (c["SUMMARY"] ?? "(no title)")
                if let l = c["LOCATION"], !l.isEmpty { line += " @ " + l }
                if let d = c["DESCRIPTION"], !d.isEmpty { line += ": " + String(d.prefix(400)) }
                if c["_kind"] == "VTODO" { line += c["STATUS"] == "COMPLETED" ? " (done)" : " (to do)" }
                out.append(line)
                cur = nil
            } else if cur != nil, cur?[k] == nil { cur?[k] = v }
        }
        return out.sorted().joined(separator: "\n")
    }

    static func vcf(_ text: String) -> String {
        var out: [String] = []
        var card: [(String, String)] = []
        let labels = ["ORG": "Organization", "TITLE": "Title", "TEL": "Phone", "EMAIL": "Email", "ADR": "Address", "BDAY": "Birthday",
                      "URL": "Web", "NOTE": "Note"]
        for (k, v) in icalLines(text) {
            if k == "BEGIN" { card = [] }
            else if k == "END" {
                let name = card.first { $0.0 == "FN" }?.1 ?? "(no name)"
                let rest = card.compactMap { k, v -> String? in
                    guard let l = labels[k], !v.isEmpty else { return nil }
                    return "- \(l): " + v.replacingOccurrences(of: ";", with: " ").trimmingCharacters(in: .whitespaces)
                }
                out.append("## \(name)\n" + rest.joined(separator: "\n"))
            } else { card.append((k, v)) }
        }
        return out.joined(separator: "\n\n")
    }
}

// MARK: - Mail (MIME)

struct Mail {
    var headers: [(String, String)] = []
    var text = ""
    var attachments: [(name: String, data: Data)] = []

    func header(_ k: String) -> String? { headers.first { $0.0.lowercased() == k.lowercased() }?.1 }

    /// An RFC 2822 date ("Tue, 03 Nov 2026 09:12:00 -0800").
    static func date(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z"] {
            f.dateFormat = fmt
            if let d = f.date(from: s.replacingOccurrences(of: #"\s*\(.*\)$"#, with: "", options: .regularExpression)) { return d }
        }
        return nil
    }

    /// The message is read as bytes (Latin-1 maps each byte to one character, losslessly);
    /// each text part is then decoded with its own charset.
    static func parse(_ data: Data) -> Mail {
        let raw = (String(data: data, encoding: .isoLatin1) ?? "").replacingOccurrences(of: "\r\n", with: "\n")
        var m = Mail()
        let (hs, body) = splitHeaders(raw)
        m.headers = hs.map { ($0.0, decodeWords(rawHeader($0.1))) }
        walk(headers: hs, body: body, into: &m, depth: 0)
        m.text = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return m
    }

    /// A header value as bytes, read as UTF-8 when it is (RFC 6532 headers), else as it was.
    static func rawHeader(_ v: String) -> String {
        guard let d = v.data(using: .isoLatin1), let u = String(data: d, encoding: .utf8) else { return v }
        return u
    }

    static func splitHeaders(_ s: String) -> ([(String, String)], String) {
        let parts = s.components(separatedBy: "\n\n")
        let head = parts.first ?? ""
        let body = parts.dropFirst().joined(separator: "\n\n")
        var hs: [(String, String)] = []
        for line in head.components(separatedBy: "\n") {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !hs.isEmpty { hs[hs.count - 1].1 += " " + line.trimmingCharacters(in: .whitespaces) }
            else if let c = line.firstIndex(of: ":") {
                hs.append((String(line[..<c]), line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)))
            }
        }
        return (hs, body)
    }

    static func param(_ header: String?, _ name: String) -> String? {
        guard let h = header,
              let r = h.range(of: #"(?i)\b"# + name + #"\*?=("[^"]*"|[^;\s]+)"#, options: .regularExpression) else { return nil }
        var v = String(h[r]); v = String(v[v.index(after: v.firstIndex(of: "=")!)...])
        if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
        if let q = v.range(of: "''"), v[..<q.lowerBound].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) {
            // RFC 2231: charset''percent-encoded
            let cs = String(v[..<q.lowerBound])
            let enc = String(v[q.upperBound...])
            var bytes = Data()
            var i = enc.startIndex
            while i < enc.endIndex {
                if enc[i] == "%", let j = enc.index(i, offsetBy: 3, limitedBy: enc.endIndex), let b = UInt8(enc[enc.index(after: i)..<j], radix: 16) {
                    bytes.append(b); i = j
                } else { bytes.append(contentsOf: Array(String(enc[i]).utf8)); i = enc.index(after: i) }
            }
            return decodeCharset(bytes, cs.isEmpty ? "utf-8" : cs)
        }
        return decodeWords(rawHeader(v))
    }

    static func walk(headers: [(String, String)], body: String, into m: inout Mail, depth: Int) {
        guard depth < 12 else { return }
        func h(_ k: String) -> String? { headers.first { $0.0.lowercased() == k }?.1 }
        let ctype = (h("content-type") ?? "text/plain").lowercased()
        let enc = (h("content-transfer-encoding") ?? "").lowercased()
        let disp = h("content-disposition")?.lowercased() ?? ""
        if ctype.hasPrefix("multipart/"), let b = param(h("content-type"), "boundary") {
            let alternative = ctype.hasPrefix("multipart/alternative")
            var parts: [([(String, String)], String)] = []
            for chunk in body.components(separatedBy: "--" + b).dropFirst() {
                if chunk.hasPrefix("--") { break }
                parts.append(splitHeaders(String(chunk.drop { $0 == "\n" })))
            }
            if alternative, let plain = parts.first(where: { ($0.0.first { $0.0.lowercased() == "content-type" }?.1.lowercased() ?? "text/plain").hasPrefix("text/plain") }) {
                walk(headers: plain.0, body: plain.1, into: &m, depth: depth + 1)
            } else {
                for p in parts { walk(headers: p.0, body: p.1, into: &m, depth: depth + 1) }
            }
            return
        }
        let data = decodeBody(body, enc)
        let filename = param(h("content-disposition"), "filename") ?? param(h("content-type"), "name")
        let cs = param(h("content-type"), "charset") ?? "utf-8"
        if disp.hasPrefix("attachment") || (filename != nil && !ctype.hasPrefix("text/")) {
            m.attachments.append((filename ?? "attachment", data))
        } else if ctype.hasPrefix("text/html") {
            m.text += Formats.htmlToText(decodeCharset(data, cs)) + "\n\n"
        } else if ctype.hasPrefix("text/") {
            m.text += decodeCharset(data, cs) + "\n\n"
        }
    }

    /// Bytes in a named charset; UTF-8 that isn't valid falls back to Windows-1252.
    static func decodeCharset(_ d: Data, _ charset: String) -> String {
        let name = charset.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")).lowercased()
        if name == "utf-8" || name == "utf8" || name == "us-ascii" || name.isEmpty {
            return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .windowsCP1252) ?? String(decoding: d, as: UTF8.self)
        }
        let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        if cf != kCFStringEncodingInvalidId {
            let enc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
            if let s = String(data: d, encoding: enc) { return s }
        }
        return String(data: d, encoding: .utf8) ?? String(data: d, encoding: .windowsCP1252) ?? String(decoding: d, as: UTF8.self)
    }

    static func decodeBody(_ body: String, _ enc: String) -> Data {
        let bytes = body.data(using: .isoLatin1) ?? Data(body.utf8)
        if enc.contains("base64") {
            var b64 = body.filter { !$0.isWhitespace }
            while b64.count % 4 != 0 { b64 += "=" }   // senders that drop the padding
            return Data(base64Encoded: b64) ?? bytes
        }
        if enc.contains("quoted-printable") { return quotedPrintable(body) }
        return bytes
    }

    static func quotedPrintable(_ s: String, underscoreSpace: Bool = false) -> Data {
        var out = Data()
        let bytes = Array(s.data(using: .isoLatin1) ?? Data(s.utf8))
        var i = 0
        func hex(_ b: UInt8) -> UInt8? {
            switch b {
            case 0x30...0x39: return b - 0x30
            case 0x41...0x46: return b - 0x37
            case 0x61...0x66: return b - 0x57
            default: return nil
            }
        }
        while i < bytes.count {
            let b = bytes[i]
            if b == UInt8(ascii: "="), i + 1 < bytes.count, bytes[i + 1] == UInt8(ascii: "\n") { i += 2; continue }
            if b == UInt8(ascii: "="), i + 2 < bytes.count, let h1 = hex(bytes[i + 1]), let h2 = hex(bytes[i + 2]) {
                out.append(h1 << 4 | h2); i += 3; continue
            }
            out.append(underscoreSpace && b == UInt8(ascii: "_") ? UInt8(ascii: " ") : b)
            i += 1
        }
        return out
    }

    /// RFC 2047 encoded words (=?charset?B?…?= / =?charset?Q?…?=), each in its own charset.
    /// Adjacent words are decoded together, so a character split across them comes out whole.
    static func decodeWords(_ s: String) -> String {
        let joined = s.replacingOccurrences(of: #"\?=\s+=\?"#, with: "?==?", options: .regularExpression)
        let re = try! NSRegularExpression(pattern: #"(?:=\?([^?]+)\?([bBqQ])\?([^?]*)\?=)+"#)
        let one = try! NSRegularExpression(pattern: #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#)
        var out = joined
        for m in re.matches(in: joined, range: NSRange(joined.startIndex..., in: joined)).reversed() {
            guard let r = Range(m.range, in: joined) else { continue }
            let run = String(joined[r])
            var bytes = Data()
            var charset = "utf-8"
            for w in one.matches(in: run, range: NSRange(run.startIndex..., in: run)) {
                let ns = run as NSString
                charset = ns.substring(with: w.range(at: 1)).split(separator: "*").first.map(String.init) ?? charset
                let kind = ns.substring(with: w.range(at: 2)).uppercased(), payload = ns.substring(with: w.range(at: 3))
                if kind == "B" {
                    var b64 = payload
                    while b64.count % 4 != 0 { b64 += "=" }
                    bytes += Data(base64Encoded: b64) ?? Data()
                } else {
                    bytes += quotedPrintable(payload, underscoreSpace: true)
                }
            }
            if let rr = Range(m.range, in: out) { out.replaceSubrange(rr, with: decodeCharset(bytes, charset)) }
        }
        return out
    }
}

// MARK: - XML helpers

/// Collects element text and attributes in one pass, for the zip-of-XML formats.
final class XMLCollector: NSObject, XMLParserDelegate {
    private var stack: [String] = []
    private var groupsOpen: [String: [String]] = [:]   // group element → texts collected inside the current one
    private var done: [String: [String]] = [:]         // "group|text" → finished group strings
    private var attrs: [String: [[String: String]]] = [:]
    private var wantedGroups: [(group: String, text: String)] = []
    private var buffer = ""
    private var data = Data()

    func parse(_ d: Data) { data = d }

    /// Text of each `text` element, joined per enclosing `group` element (e.g. a sheet string, a slide paragraph).
    func groups(of group: String, text: String) -> [String] {
        let key = group + "|" + text
        if done[key] == nil { wantedGroups.append((group, text)); run() }
        return done[key] ?? []
    }

    func attributes(of element: String, _ name: String) -> [String] {
        if attrs.isEmpty { run() }
        return (attrs[element] ?? []).compactMap { $0[name] }
    }

    private func run() {
        stack = []; groupsOpen = [:]; buffer = ""
        for w in wantedGroups { done[w.group + "|" + w.text] = [] }
        attrs = [:]
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName q: String?, attributes a: [String: String] = [:]) {
        stack.append(name)
        attrs[name, default: []].append(a)
        for w in wantedGroups where w.group == name { groupsOpen[w.group + "|" + w.text] = [] }
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) { buffer += s }
    func parser(_ parser: XMLParser, foundCDATA d: Data) { buffer += String(decoding: d, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName q: String?) {
        for w in wantedGroups {
            let key = w.group + "|" + w.text
            if name == w.text, groupsOpen[key] != nil { groupsOpen[key]!.append(buffer) }
            if name == w.group, let parts = groupsOpen[key] { done[key, default: []].append(parts.joined()); groupsOpen[key] = nil }
        }
        buffer = ""
        _ = stack.popLast()
    }
}

/// One worksheet's cells, placed by their A1 references.
final class SheetParser: NSObject, XMLParserDelegate {
    let shared: [String]
    var rows: [[String]] = []
    private var row: [Int: String] = [:]
    private var col = 0, next = 0, type = "", buffer = "", inValue = false

    init(shared: [String]) { self.shared = shared }

    func parse(_ d: Data) { let p = XMLParser(data: d); p.delegate = self; p.parse() }

    /// "AB12" → 27; nil when it isn't a real column (Excel stops at XFD).
    static func column(_ ref: String) -> Int? {
        let letters = ref.prefix { $0.isASCII && $0.isLetter }.uppercased()
        guard !letters.isEmpty, letters.count <= 3 else { return nil }
        return letters.unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName q: String?, attributes a: [String: String] = [:]) {
        switch name {
        case "row": row = [:]; next = 0
        case "c":
            // Cells may leave out "r": then each one is the next column.
            col = a["r"].flatMap(Self.column) ?? (a["r"] == nil ? next : -1)
            next = col + 1
            type = a["t"] ?? "n"; buffer = ""
        case "v", "t": inValue = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters s: String) { if inValue { buffer += s } }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName q: String?) {
        switch name {
        case "v", "t": inValue = false
        case "c":
            var v = buffer
            if type == "s" { v = Int(v).flatMap { $0 >= 0 && $0 < shared.count ? shared[$0] : nil } ?? "" }
            if type == "b" { v = v == "1" ? "TRUE" : "FALSE" }
            v = v.replacingOccurrences(of: "_x000D_", with: "").replacingOccurrences(of: "_x000A_", with: "\n")
                .replacingOccurrences(of: "_x0009_", with: "\t")
            if col >= 0, col < Formats.maxColumns { row[col] = v }
        case "row":
            if let maxc = row.keys.max() { rows.append((0...maxc).map { row[$0] ?? "" }) }
        default: break
        }
    }
}
