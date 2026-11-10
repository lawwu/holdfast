import AppKit
import SwiftUI

// MARK: - Block parser

/// Markdown blocks, enough for typical notes: headings, paragraphs,
/// nested and task lists, quotes and callouts, fenced code, tables, rules.
enum MDBlockKind {
    case heading(Int)
    case paragraph
    case listItem(level: Int, marker: String, checked: Bool?)
    case quote(callout: String?)
    case code(lang: String)
    case table(header: [String], rows: [[String]])
    case rule
}

struct MDBlock: Identifiable {
    var id: Int
    var kind: MDBlockKind
    var text: String
    /// Seconds into a recording, for transcript lines "[hh:mm:ss] …".
    var time: Double?
    var isHeading: Bool { if case .heading = kind { return true } else { return false } }
}

enum MarkdownParser {
    static let listRe = try! NSRegularExpression(pattern: #"^(\s*)([-*+]|\d+[.)])\s+(\[[ xX]\]\s+)?(.*)$"#)

    static func parse(_ body: String) -> [MDBlock] {
        var out: [MDBlock] = []
        let lines = body.components(separatedBy: "\n")
        var i = 0
        var para: [String] = []
        func add(_ k: MDBlockKind, _ t: String, time: Double? = nil) { out.append(MDBlock(id: out.count, kind: k, text: t, time: time)) }
        func flushPara() {
            // Soft line breaks are spaces; a line ending in two spaces or "\\" is a hard break.
            guard !para.isEmpty else { return }
            var text = ""
            for (i, l) in para.enumerated() {
                let hard = l.hasSuffix("  ") || l.hasSuffix("\\")
                text += hard ? String(l.trimmingCharacters(in: .whitespaces).dropLast(l.hasSuffix("\\") ? 1 : 0)) : l
                if i < para.count - 1 { text += hard ? "\n" : " " }
            }
            add(.paragraph, text)
            para = []
        }
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { flushPara(); i += 1; continue }
            // Fenced code
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                flushPara()
                let fence = String(t.prefix(3))
                let lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) { code.append(lines[i]); i += 1 }
                add(.code(lang: lang), code.joined(separator: "\n"))
                i += 1
                continue
            }
            // Heading
            if t.hasPrefix("#"), let sp = t.firstIndex(of: " "), t[..<sp].allSatisfy({ $0 == "#" }), t[..<sp].count <= 6 {
                flushPara()
                add(.heading(t[..<sp].count), String(t[sp...]).trimmingCharacters(in: .whitespaces))
                i += 1
                continue
            }
            // Rule
            if t.count >= 3, Set(t.replacingOccurrences(of: " ", with: "")).count == 1, ["-", "*", "_"].contains(t.first!) {
                flushPara(); add(.rule, ""); i += 1; continue
            }
            // Table: a pipe row followed by a separator row
            if t.hasPrefix("|"), i + 1 < lines.count,
               lines[i + 1].trimmingCharacters(in: .whitespaces).range(of: #"^\|?\s*:?-{2,}"#, options: .regularExpression) != nil {
                flushPara()
                let header = cells(t)
                var rows: [[String]] = []
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(cells(lines[i].trimmingCharacters(in: .whitespaces))); i += 1
                }
                add(.table(header: header, rows: rows), "")
                continue
            }
            // Quote / callout (consecutive ">" lines)
            if t.hasPrefix(">") {
                flushPara()
                var q: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    q.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                }
                var callout: String?
                if let f = q.first, f.hasPrefix("[!"), let close = f.firstIndex(of: "]") {
                    callout = String(f[f.index(f.startIndex, offsetBy: 2)..<close]).lowercased()
                    let title = f[f.index(after: close)...].trimmingCharacters(in: .whitespaces)
                    q[0] = title.isEmpty ? callout!.capitalized : "**\(title)**"
                }
                add(.quote(callout: callout), q.joined(separator: "\n"))
                continue
            }
            // List item
            let ns = line as NSString
            if let m = listRe.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                flushPara()
                let indent = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: "\t", with: "    ").count
                let box = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)).lowercased().contains("x") : nil
                add(.listItem(level: indent / 2, marker: ns.substring(with: m.range(at: 2)), checked: box), ns.substring(with: m.range(at: 4)))
                i += 1
                continue
            }
            // Transcript line: its own block, with a time for the play button
            if let tm = timestamp(t) {
                flushPara(); add(.paragraph, t, time: tm); i += 1; continue
            }
            // A wrapped line straight after a list item continues that item.
            if para.isEmpty, i > 0, !lines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty,
               let last = out.last, case .listItem = last.kind {
                out[out.count - 1].text += " " + t
                i += 1
                continue
            }
            para.append(line.hasSuffix("  ") ? t + "  " : t)
            i += 1
        }
        flushPara()
        return out
    }

    static func cells(_ row: String) -> [String] {
        var r = row
        if r.hasPrefix("|") { r.removeFirst() }
        if r.hasSuffix("|") { r.removeLast() }
        return r.replacingOccurrences(of: "\\|", with: "\u{1}").components(separatedBy: "|")
            .map { $0.replacingOccurrences(of: "\u{1}", with: "|").trimmingCharacters(in: .whitespaces) }
    }

    static func timestamp(_ line: String) -> Double? {
        if line.hasPrefix("["), line.count > 10, line.dropFirst(9).first == "]" { return parseTime(String(line.dropFirst().prefix(8))) }
        if line.hasPrefix("**"), line.count > 12, line.dropFirst(10).hasPrefix("**") { return parseTime(String(line.dropFirst(2).prefix(8))) }
        return nil
    }
}

// MARK: - Inline rendering

/// Inline Markdown for the reader. Wikilinks become `holdfast-note:` links and
/// relative `.md` links become `holdfast-rel:` links, both opened in the app.
func noteInline(_ s: String, size: CGFloat = 14.5) -> AttributedString {
    var md = s
    let ns = md as NSString
    var replaced = md
    for m in LinkParser.wiki.matches(in: md, range: NSRange(location: 0, length: ns.length)).reversed() {
        let target = ns.substring(with: m.range(at: 1))
        let heading = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
        let label = m.range(at: 3).location != NSNotFound ? ns.substring(with: m.range(at: 3)) : target
        let url = "holdfast-note:" + (target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target)
            + (heading.isEmpty ? "" : "#" + (heading.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? ""))
        replaced = (replaced as NSString).replacingCharacters(in: m.range, with: "[\(label)](\(url))")
    }
    md = replaced
    md = md.replacingOccurrences(of: #"\]\((?![a-zA-Z][a-zA-Z0-9+.-]*:)([^)\s]+\.md(?:#[^)\s]*)?)\)"#,
                                 with: "](holdfast-rel:$1)", options: .regularExpression)
    guard var out = try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
        return AttributedString(s)
    }
    let runs = out.runs.map { ($0.range, $0.inlinePresentationIntent, $0.link) }
    for (r, intent, link) in runs {
        if intent?.contains(.code) == true {
            out[r].font = .system(size: size - 1.5, design: .monospaced)
            out[r].backgroundColor = Color.primary.opacity(0.07)
        }
        if let l = link {
            out[r].foregroundColor = Theme.accent
            if l.scheme == "holdfast-note" || l.scheme == "holdfast-rel" {
                out[r].underlineStyle = nil
            }
        }
    }
    return out
}

// MARK: - Reader views

struct MDTableView: View {
    var header: [String]
    var rows: [[String]]
    var body: some View {
        // Cells wrap within the available width (a horizontal scroll view measured
        // them as one line and rows overlapped).
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { _, h in
                    cell(h, bold: true)
                }
            }
            .background(Theme.canvas)
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                Divider().gridCellUnsizedAxes(.horizontal)
                GridRow {
                    ForEach(0..<header.count, id: \.self) { c in
                        cell(c < row.count ? row[c] : "", bold: false)
                    }
                }
                .background(i % 2 == 1 ? Color.primary.opacity(0.025) : .clear)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.cardStroke))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    func cell(_ text: String, bold: Bool) -> some View {
        Text(noteInline(text, size: 13))
            .font(.system(size: 14.5, weight: bold ? .semibold : .regular))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 10).padding(.vertical, bold ? 7 : 6)
    }
}

struct MDBlockView: View {
    var block: MDBlock
    var body: some View {
        switch block.kind {
        case .heading(let l):
            Text(noteInline(block.text))
                .font(l == 1 ? .system(size: 22, weight: .bold, design: .serif)
                      : l == 2 ? .system(size: 18, weight: .semibold) : l == 3 ? .system(size: 15.5, weight: .semibold)
                      : .system(size: 16, weight: .semibold))
                .foregroundStyle(l >= 4 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .padding(.top, l <= 2 ? 14 : 8)
        case .paragraph:
            Text(noteInline(block.text)).font(.system(size: 16)).lineSpacing(4)
        case .listItem(let level, let marker, let checked):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let checked {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                } else if marker.first?.isNumber == true {
                    Text(marker).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.accent).monospacedDigit()
                } else {
                    Circle().fill(Theme.accent.opacity(0.7)).frame(width: 5, height: 5)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                }
                Text(noteInline(block.text)).font(.system(size: 16)).lineSpacing(3)
                    .strikethrough(checked == true, color: .secondary)
                    .foregroundStyle(checked == true ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            }
            .padding(.leading, CGFloat(level) * 20 + 2)
        case .quote(let callout):
            HStack(alignment: .top, spacing: 10) {
                if let callout {
                    Image(systemName: calloutIcon(callout)).foregroundStyle(calloutColor(callout))
                }
                Text(noteInline(block.text))
                    .font(callout == nil ? .system(size: 20, weight: .regular, design: .serif) : .system(size: 16))
                    .lineSpacing(4)
                    .foregroundStyle(callout == nil ? Theme.accent : Theme.ink)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8).padding(.horizontal, 12)
            .background(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(callout.map { calloutColor($0).opacity(0.09) } ?? .clear)
                    Rectangle().fill(callout.map(calloutColor) ?? Theme.accent).frame(width: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
        case .code(let lang):
            VStack(alignment: .leading, spacing: 4) {
                if !lang.isEmpty { Text(lang).font(Theme.caption2.weight(.medium)).foregroundStyle(.tertiary) }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(block.text).font(.system(size: 13.5, design: .monospaced)).lineSpacing(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
        case .table(let header, let rows):
            MDTableView(header: header, rows: rows)
        case .rule:
            Divider().padding(.vertical, 6)
        }
    }

    func calloutIcon(_ c: String) -> String {
        switch c {
        case "warning", "caution", "attention": return "exclamationmark.triangle.fill"
        case "tip", "hint", "important": return "lightbulb.fill"
        case "question", "faq", "help": return "questionmark.circle.fill"
        case "danger", "error", "bug": return "xmark.octagon.fill"
        case "success", "check", "done": return "checkmark.circle.fill"
        default: return "info.circle.fill"
        }
    }

    func calloutColor(_ c: String) -> Color {
        switch c {
        case "warning", "caution", "attention": return .orange
        case "tip", "hint", "important", "success", "check", "done": return .green
        case "danger", "error", "bug": return .red
        default: return Theme.accent
        }
    }
}
