import Foundation
import QuickLookUI
import UniformTypeIdentifiers

// Holdfast's Quick Look preview for Markdown: press Space on a note in Finder
// and see it rendered (headings, tables, task lists, properties) instead of
// raw text. Built by scripts/make_app.sh into Holdfast.app/Contents/PlugIns as
// a data-based preview extension: it turns the file into HTML and Quick Look
// shows that. Nothing is fetched; the HTML has no external resources.

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let text = (try? String(contentsOf: request.fileURL, encoding: .utf8)) ?? ""
        let html = MarkdownHTML.page(text, name: request.fileURL.deletingPathExtension().lastPathComponent)
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 820, height: 1000)) { _ in
            Data(html.utf8)
        }
    }
}

/// A small Markdown-to-HTML renderer: enough for notes (no external libraries
/// in an extension that must stay sandboxed and small).
enum MarkdownHTML {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func sub(_ s: String, _ pattern: String, _ template: String) -> String {
        s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }

    /// Inline Markdown: code, bold, italic, links, wiki links.
    static func inline(_ raw: String) -> String {
        var codes: [String] = []
        var s = sub(raw, "`([^`]+)`", "\u{1}$1\u{2}")
        // Pull code spans out first so their contents stay literal.
        while let a = s.range(of: "\u{1}"), let b = s.range(of: "\u{2}", range: a.upperBound..<s.endIndex) {
            codes.append(String(s[a.upperBound..<b.lowerBound]))
            s.replaceSubrange(a.lowerBound..<b.upperBound, with: "\u{3}\(codes.count - 1)\u{4}")
        }
        s = esc(s)
        s = sub(s, #"\[\[([^\]|]+)\|([^\]]+)\]\]"#, "<span class=\"wl\">$2</span>")
        s = sub(s, #"\[\[([^\]]+)\]\]"#, "<span class=\"wl\">$1</span>")
        s = sub(s, #"!\[([^\]]*)\]\([^)]+\)"#, "<span class=\"wl\">[image: $1]</span>")
        s = sub(s, #"\[([^\]]+)\]\(([^)\s]+)\)"#, "<a href=\"$2\">$1</a>")
        s = sub(s, #"\*\*([^*]+)\*\*"#, "<strong>$1</strong>")
        s = sub(s, #"__([^_]+)__"#, "<strong>$1</strong>")
        s = sub(s, #"(?<![\w*])\*([^*\n]+)\*(?![\w*])"#, "<em>$1</em>")
        s = sub(s, #"(?<![\w_])_([^_\n]+)_(?![\w_])"#, "<em>$1</em>")
        s = sub(s, #"==([^=]+)=="#, "<mark>$1</mark>")
        for (i, c) in codes.enumerated() { s = s.replacingOccurrences(of: "\u{3}\(i)\u{4}", with: "<code>\(esc(c))</code>") }
        return s
    }

    static func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func body(_ md: String) -> String {
        var out: [String] = []
        var lines = md.components(separatedBy: "\n")
        var i = 0
        // Frontmatter as a property table.
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            let props = lines[1..<end].compactMap { l -> (String, String)? in
                guard let c = l.firstIndex(of: ":") else { return nil }
                var v = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
                return (l[..<c].trimmingCharacters(in: .whitespaces), v)
            }
            if !props.isEmpty {
                out.append("<table class=\"props\">" + props.map { "<tr><th>\(esc($0.0))</th><td>\(inline($0.1))</td></tr>" }.joined() + "</table>")
            }
            lines = Array(lines[(end + 1)...])
        }
        var para: [String] = []
        func flush() { if !para.isEmpty { out.append("<p>" + para.map(inline).joined(separator: " ") + "</p>"); para = [] } }
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                flush()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { code.append(lines[i]); i += 1 }
                out.append("<pre><code>" + esc(code.joined(separator: "\n")) + "</code></pre>")
                i += 1
                continue
            }
            if t.isEmpty { flush(); i += 1; continue }
            if let m = t.range(of: #"^#{1,6} "#, options: .regularExpression) {
                flush()
                let level = t[m].count - 1
                out.append("<h\(level)>\(inline(String(t[m.upperBound...])))</h\(level)>")
                i += 1; continue
            }
            if t.range(of: #"^(-{3,}|\*{3,}|_{3,})$"#, options: .regularExpression) != nil { flush(); out.append("<hr>"); i += 1; continue }
            if t.hasPrefix("|"), i + 1 < lines.count,
               lines[i + 1].trimmingCharacters(in: .whitespaces).range(of: #"^\|?\s*:?-{2,}"#, options: .regularExpression) != nil {
                flush()
                var html = "<table><thead><tr>" + cells(t).map { "<th>\(inline($0))</th>" }.joined() + "</tr></thead><tbody>"
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    html += "<tr>" + cells(lines[i]).map { "<td>\(inline($0))</td>" }.joined() + "</tr>"
                    i += 1
                }
                out.append(html + "</tbody></table>")
                continue
            }
            if t.hasPrefix(">") {
                flush()
                var q: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    q.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                }
                out.append("<blockquote>" + inline(q.joined(separator: " ")) + "</blockquote>")
                continue
            }
            let bullet = #"^\s*([-*+]|\d+[.)])\s+"#
            if line.range(of: bullet, options: .regularExpression) != nil {
                flush()
                let ordered = t.first?.isNumber == true
                var items: [String] = []
                while i < lines.count, let r = lines[i].range(of: bullet, options: .regularExpression) {
                    let indent = lines[i].prefix { $0 == " " || $0 == "\t" }.count
                    var item = String(lines[i][r.upperBound...])
                    var cls = indent >= 2 ? " class=\"sub\"" : ""
                    if item.hasPrefix("[ ] ") { item = "<span class=\"box\"></span>" + inline(String(item.dropFirst(4))); cls = " class=\"task\(indent >= 2 ? " sub" : "")\"" }
                    else if item.lowercased().hasPrefix("[x] ") { item = "<span class=\"box done\">✓</span><s>" + inline(String(item.dropFirst(4))) + "</s>"; cls = " class=\"task\(indent >= 2 ? " sub" : "")\"" }
                    else { item = inline(item) }
                    items.append("<li\(cls)>\(item)</li>")
                    i += 1
                }
                out.append((ordered ? "<ol>" : "<ul>") + items.joined() + (ordered ? "</ol>" : "</ul>"))
                continue
            }
            para.append(t)
            i += 1
        }
        flush()
        return out.joined(separator: "\n")
    }

    static func page(_ md: String, name: String) -> String {
        """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <style>
        :root { color-scheme: light dark; --ink: #1d1f23; --muted: #6b7079; --line: #e3e5e9; --soft: #f4f5f7; --accent: #2a78d6; }
        @media (prefers-color-scheme: dark) { :root { --ink: #eceef1; --muted: #9aa0a9; --line: #33363c; --soft: #24272c; --accent: #4b93ea; } }
        body { font: 14px/1.6 -apple-system, system-ui, sans-serif; color: var(--ink); max-width: 760px; margin: 28px auto; padding: 0 28px; }
        h1 { font-size: 26px; margin: 0 0 14px; } h2 { font-size: 19px; margin: 26px 0 8px; } h3 { font-size: 16px; margin: 20px 0 6px; }
        h4, h5, h6 { font-size: 14px; margin: 16px 0 4px; color: var(--muted); }
        p { margin: 0 0 10px; } a { color: var(--accent); text-decoration: none; }
        .wl { color: var(--accent); }
        code { font: 12.5px ui-monospace, Menlo, monospace; background: var(--soft); padding: 1px 4px; border-radius: 4px; }
        pre { background: var(--soft); padding: 10px 12px; border-radius: 8px; overflow-x: auto; } pre code { padding: 0; background: none; }
        table { border-collapse: collapse; margin: 8px 0 14px; font-size: 13px; width: 100%; }
        th, td { border-bottom: 1px solid var(--line); padding: 5px 8px; text-align: left; vertical-align: top; }
        th { color: var(--muted); font-weight: 600; }
        table.props { width: auto; margin-bottom: 18px; font-size: 12.5px; } table.props th { padding-right: 18px; font-weight: 500; }
        blockquote { margin: 8px 0; padding: 2px 14px; border-left: 3px solid var(--line); color: var(--muted); }
        ul, ol { padding-left: 22px; margin: 4px 0 10px; } li.sub { margin-left: 18px; }
        li.task { list-style: none; margin-left: -20px; }
        .box { display: inline-block; width: 12px; height: 12px; border: 1.5px solid var(--muted); border-radius: 50%; margin-right: 7px; vertical-align: -1px; font-size: 9px; line-height: 12px; text-align: center; }
        .box.done { background: var(--accent); border-color: var(--accent); color: white; }
        s { color: var(--muted); } hr { border: 0; border-top: 1px solid var(--line); margin: 18px 0; }
        mark { background: #ffe58a66; color: inherit; }
        footer { margin-top: 30px; font-size: 11px; color: var(--muted); }
        </style><title>\(esc(name))</title></head><body>
        \(body(md))
        <footer>Holdfast · previewed on this Mac</footer>
        </body></html>
        """
    }
}
