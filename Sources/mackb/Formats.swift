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

    static func text(_ url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "xlsx":
            return try xlsxSheets(url).map { s in "## Sheet: \(s.name)\n\n" + s.rows.map(csvLine).joined(separator: "\n") }
                .joined(separator: "\n\n")
        case "pptx": return try pptx(url)
        case "epub": return try epub(url)
        case "eml": return mailText(Mail.parse(try Data(contentsOf: url)))
        case "ics": return ics(try String(contentsOf: url, encoding: .utf8))
        case "vcf": return vcf(try String(contentsOf: url, encoding: .utf8))
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
            if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
            return String(decoding: try Data(contentsOf: url), as: UTF8.self)
        }
    }

    // MARK: zip

    static func zipEntries(_ url: URL) throws -> [String] {
        try run("/usr/bin/unzip", ["-Z1", url.path]).split(separator: "\n").map(String.init)
    }

    static func zipRead(_ url: URL, _ entry: String) throws -> Data {
        // unzip treats [ ] * ? as wildcards in entry names.
        var esc = ""
        for ch in entry { if "[]*?\\".contains(ch) { esc.append("\\") }; esc.append(ch) }
        return Data(try run("/usr/bin/unzip", ["-p", url.path, esc]).utf8)
    }

    // MARK: spreadsheets (xlsx)

    struct Sheet { var name: String; var rows: [[String]] }

    static func xlsxSheets(_ url: URL) throws -> [Sheet] {
        let entries = try zipEntries(url)
        var shared: [String] = []
        if entries.contains("xl/sharedStrings.xml") {
            let x = XMLCollector()
            x.parse(try zipRead(url, "xl/sharedStrings.xml"))
            shared = x.groups(of: "si", text: "t")
        }
        var names: [String] = []
        if entries.contains("xl/workbook.xml") {
            let x = XMLCollector()
            x.parse(try zipRead(url, "xl/workbook.xml"))
            names = x.attributes(of: "sheet", "name")
        }
        let sheets = entries.filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted { (Int($0.filter(\.isNumber)) ?? 0) < (Int($1.filter(\.isNumber)) ?? 0) }
        return try sheets.enumerated().map { i, e in
            let p = SheetParser(shared: shared)
            p.parse(try zipRead(url, e))
            return Sheet(name: i < names.count ? names[i] : "Sheet\(i + 1)", rows: p.rows)
        }
    }

    static func csvLine(_ row: [String]) -> String {
        row.map { c in c.contains(where: { ",\"\n".contains($0) }) ? "\"" + c.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : c }
            .joined(separator: ",")
    }

    // MARK: slides (pptx)

    static func pptx(_ url: URL) throws -> String {
        let slides = try zipEntries(url).filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
            .sorted { (Int($0.filter(\.isNumber)) ?? 0) < (Int($1.filter(\.isNumber)) ?? 0) }
        return try slides.enumerated().map { i, e in
            let x = XMLCollector()
            x.parse(try zipRead(url, e))
            return "## Slide \(i + 1)\n\n" + x.groups(of: "a:p", text: "a:t").filter { !$0.isEmpty }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    // MARK: ebooks (epub)

    static func epub(_ url: URL) throws -> String {
        let entries = try zipEntries(url)
        var order: [String] = []
        if entries.contains("META-INF/container.xml") {
            let c = XMLCollector()
            c.parse(try zipRead(url, "META-INF/container.xml"))
            if let opf = c.attributes(of: "rootfile", "full-path").first, entries.contains(opf) {
                let o = XMLCollector()
                o.parse(try zipRead(url, opf))
                let base = (opf as NSString).deletingLastPathComponent
                let hrefs = Dictionary(zip(o.attributes(of: "item", "id"), o.attributes(of: "item", "href")), uniquingKeysWith: { a, _ in a })
                order = o.attributes(of: "itemref", "idref").compactMap { hrefs[$0] }
                    .map { base.isEmpty ? $0 : base + "/" + $0 }
                    .map { $0.removingPercentEncoding ?? $0 }
            }
        }
        if order.isEmpty { order = entries.filter { $0.hasSuffix(".xhtml") || $0.hasSuffix(".html") || $0.hasSuffix(".htm") }.sorted() }
        return try order.filter { entries.contains($0) }
            .map { htmlToText(String(decoding: try zipRead(url, $0), as: UTF8.self)) }
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func htmlToText(_ html: String) -> String {
        var s = html.replacingOccurrences(of: #"(?is)<(script|style|head)[^>]*>.*?</\1>"#, with: "", options: .regularExpression)
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
            let key = l[..<c].split(separator: ";").first.map(String.init)?.uppercased() ?? ""
            let v = String(l[l.index(after: c)...]).replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\N", with: " ")
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

    static func parse(_ data: Data) -> Mail {
        let raw = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
        var m = Mail()
        let (hs, body) = splitHeaders(raw)
        m.headers = hs.map { ($0.0, decodeWords($0.1)) }
        walk(headers: hs, body: body, into: &m)
        m.text = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return m
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
        if v.lowercased().hasPrefix("utf-8''") { v = (String(v.dropFirst(7)).removingPercentEncoding) ?? v }
        return decodeWords(v)
    }

    static func walk(headers: [(String, String)], body: String, into m: inout Mail) {
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
                walk(headers: plain.0, body: plain.1, into: &m)
            } else {
                for p in parts { walk(headers: p.0, body: p.1, into: &m) }
            }
            return
        }
        let data = decodeBody(body, enc)
        let filename = param(h("content-disposition"), "filename") ?? param(h("content-type"), "name")
        if disp.hasPrefix("attachment") || (filename != nil && !ctype.hasPrefix("text/")) {
            m.attachments.append((filename ?? "attachment", data))
        } else if ctype.hasPrefix("text/html") {
            m.text += Formats.htmlToText(String(decoding: data, as: UTF8.self)) + "\n\n"
        } else if ctype.hasPrefix("text/") {
            let cs = param(h("content-type"), "charset")?.lowercased() ?? "utf-8"
            let s = cs.contains("8859") || cs.contains("1252") ? (String(data: data, encoding: .isoLatin1) ?? "") : String(decoding: data, as: UTF8.self)
            m.text += s + "\n\n"
        }
    }

    static func decodeBody(_ body: String, _ enc: String) -> Data {
        if enc.contains("base64") {
            return Data(base64Encoded: body.filter { !$0.isWhitespace }) ?? Data(body.utf8)
        }
        if enc.contains("quoted-printable") { return quotedPrintable(body) }
        return Data(body.utf8)
    }

    static func quotedPrintable(_ s: String, underscoreSpace: Bool = false) -> Data {
        var out = Data()
        let bytes = Array(s.utf8)
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == UInt8(ascii: "="), i + 1 < bytes.count, bytes[i + 1] == UInt8(ascii: "\n") { i += 2; continue }
            if b == UInt8(ascii: "="), i + 2 < bytes.count, let v = UInt8(String(decoding: bytes[(i + 1)...(i + 2)], as: UTF8.self), radix: 16) {
                out.append(v); i += 3; continue
            }
            out.append(underscoreSpace && b == UInt8(ascii: "_") ? UInt8(ascii: " ") : b)
            i += 1
        }
        return out
    }

    /// RFC 2047 encoded words: =?utf-8?B?…?= and =?utf-8?Q?…?=.
    static func decodeWords(_ s: String) -> String {
        let re = try! NSRegularExpression(pattern: #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#)
        var out = s
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            let ns = s as NSString
            let kind = ns.substring(with: m.range(at: 2)).uppercased(), payload = ns.substring(with: m.range(at: 3))
            let data = kind == "B" ? (Data(base64Encoded: payload) ?? Data()) : quotedPrintable(payload, underscoreSpace: true)
            if let r = Range(m.range, in: out) { out.replaceSubrange(r, with: String(decoding: data, as: UTF8.self)) }
        }
        return out.replacingOccurrences(of: #"\?=\s+=\?"#, with: "?==?", options: .regularExpression)
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
    private var col = 0, type = "", buffer = "", inValue = false

    init(shared: [String]) { self.shared = shared }

    func parse(_ d: Data) { let p = XMLParser(data: d); p.delegate = self; p.parse() }

    static func column(_ ref: String) -> Int {
        ref.prefix { $0.isLetter }.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName q: String?, attributes a: [String: String] = [:]) {
        switch name {
        case "row": row = [:]
        case "c": col = Self.column(a["r"] ?? "A"); type = a["t"] ?? "n"; buffer = ""
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
            if type == "s", let i = Int(v), i < shared.count { v = shared[i] }
            if type == "b" { v = v == "1" ? "TRUE" : "FALSE" }
            if col >= 0 { row[col] = v }
        case "row":
            if let maxc = row.keys.max() { rows.append((0...maxc).map { row[$0] ?? "" }) }
        default: break
        }
    }
}
