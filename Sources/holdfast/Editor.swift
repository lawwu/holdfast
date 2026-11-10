import AppKit
import SwiftUI

/// A Markdown source editor in the style of Obsidian's source mode: a native
/// NSTextView (undo, find bar, spell check, smooth scrolling) whose text is
/// styled as you type. Syntax characters stay visible but recede; links and
/// [[wikilinks]] are clickable and open in the app.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    /// Notes offered after `[[` (and their headings after `#`).
    var notes: [Note] = []
    var onOpenLink: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = LinkTextView.scrollableTextView()
        scroll.drawsBackground = false
        let tv = scroll.documentView as! NSTextView
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 36, height: 28)
        tv.font = MarkdownStyler.base
        tv.typingAttributes = MarkdownStyler.baseAttributes
        tv.linkTextAttributes = [.foregroundColor: NSColor(Theme.accent), .cursor: NSCursor.pointingHand]
        tv.insertionPointColor = NSColor(Theme.accent)
        tv.string = text
        MarkdownStyler.style(tv.textStorage!)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        let tv = scroll.documentView as! NSTextView
        if tv.string != text {
            let sel = tv.selectedRanges
            tv.string = text
            MarkdownStyler.style(tv.textStorage!)
            let len = (text as NSString).length
            tv.selectedRanges = sel.map { NSValue(range: NSRange(location: min($0.rangeValue.location, len), length: 0)) }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        init(_ p: MarkdownEditor) { parent = p }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            MarkdownStyler.style(tv.textStorage!)
            tv.typingAttributes = MarkdownStyler.baseAttributes
            parent.text = tv.string
            // Inside [[…: show note suggestions as you type, as Obsidian does.
            if let ltv = tv as? LinkTextView, !ltv.completing, ltv.wikiPartialRange() != nil {
                DispatchQueue.main.async { ltv.complete(nil) }
            }
        }

        /// Suggestions after `[[`: notes whose name, title or path contain what
        /// was typed; after `#`, that note's headings.
        func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange,
                      indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
            guard let ltv = textView as? LinkTextView, let r = ltv.wikiPartialRange() else { return words }
            let partial = (textView.string as NSString).substring(with: r)
            index?.pointee = 0
            let notes = parent.notes
            var nameCount: [String: Int] = [:]
            for n in notes { nameCount[n.name.lowercased(), default: 0] += 1 }
            func linkText(_ n: Note) -> String { nameCount[n.name.lowercased()] == 1 ? n.name : n.id }
            if let hash = partial.firstIndex(of: "#") {
                let target = String(partial[..<hash]).lowercased()
                let hq = String(partial[partial.index(after: hash)...]).lowercased()
                guard let n = notes.first(where: { $0.name.lowercased() == target || $0.id.lowercased() == target }) else { return [] }
                return MarkdownParser.parse(n.body).filter(\.isHeading).map(\.text)
                    .filter { hq.isEmpty || $0.lowercased().contains(hq) }
                    .prefix(40).map { "\(String(partial[..<hash]))#\($0)" }
            }
            let q = partial.lowercased()
            let scored: [(String, Int)] = notes.compactMap { n in
                let name = n.name.lowercased(), title = n.title.lowercased(), id = n.id.lowercased()
                let s: Int
                if q.isEmpty { s = 3 }
                else if name.hasPrefix(q) || title.hasPrefix(q) { s = 0 }
                else if name.contains(q) || title.contains(q) { s = 1 }
                else if id.contains(q) { s = 2 }
                else { return nil }
                return (linkText(n), s)
            }
            return scored.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.count < $1.0.count }.prefix(50).map(\.0)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let u = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)) else { return false }
            parent.onOpenLink(u)  // the caller reads ⌘ (new tab) and ⌥ (preview)
            return true
        }
    }
}

enum MarkdownStyler {
    static let size: CGFloat = 14.5
    static let base = NSFont.systemFont(ofSize: size)
    static let mono = NSFont.monospacedSystemFont(ofSize: size - 1.5, weight: .regular)
    static let para: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 4
        p.paragraphSpacing = 2
        return p
    }()
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: base, .foregroundColor: NSColor(Theme.ink), .paragraphStyle: para]
    }
    static let accent = NSColor(Theme.accent)
    static let faint = NSColor.tertiaryLabelColor
    static let codeBg = NSColor.labelColor.withAlphaComponent(0.06)

    static let reBold = try! NSRegularExpression(pattern: #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    static let reItalic = try! NSRegularExpression(pattern: #"(?<![*_\w])([*_])(?=\S)([^*_\n]+?)(?<=\S)\1(?![*_\w])"#)
    static let reCode = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)
    static let reMdLink = try! NSRegularExpression(pattern: #"\[([^\]\n]*)\]\(([^)\s]+)\)"#)
    static let reTime = try! NSRegularExpression(pattern: #"^\[\d\d:\d\d:\d\d\]"#, options: .anchorsMatchLines)

    static func font(_ f: NSFont, adding t: NSFontDescriptor.SymbolicTraits) -> NSFont {
        NSFont(descriptor: f.fontDescriptor.withSymbolicTraits(f.fontDescriptor.symbolicTraits.union(t)), size: f.pointSize) ?? f
    }

    static func style(_ ts: NSTextStorage) {
        let s = ts.string as NSString
        let full = NSRange(location: 0, length: s.length)
        ts.beginEditing()
        ts.setAttributes(baseAttributes, range: full)

        // Line-level: frontmatter, fences, headings, quotes, lists, tables.
        var inFence = false
        var inFront = false
        var lineNo = 0
        s.enumerateSubstrings(in: full, options: [.byLines, .substringNotRequired]) { _, r, _, _ in
            let line = s.substring(with: r)
            let t = line.trimmingCharacters(in: .whitespaces)
            defer { lineNo += 1 }
            if lineNo == 0, t == "---" { inFront = true }
            if inFront {
                ts.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor], range: r)
                if lineNo > 0, t == "---" { inFront = false }
                return
            }
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                inFence.toggle()
                ts.addAttributes([.font: mono, .foregroundColor: faint], range: r)
                return
            }
            if inFence {
                ts.addAttributes([.font: mono, .backgroundColor: codeBg], range: r)
                return
            }
            if t.hasPrefix("#"), let sp = t.firstIndex(of: " "), t[..<sp].allSatisfy({ $0 == "#" }), t[..<sp].count <= 6 {
                let level = t[..<sp].count
                let sizes: [CGFloat] = [24, 20, 17, 15.5, 14.5, 14.5]
                ts.addAttribute(.font, value: NSFont.systemFont(ofSize: sizes[level - 1], weight: level <= 2 ? .bold : .semibold), range: r)
                let lead = (line as NSString).range(of: String(t[..<sp]))
                ts.addAttribute(.foregroundColor, value: faint, range: NSRange(location: r.location + lead.location, length: lead.length))
                return
            }
            if t.hasPrefix(">") {
                ts.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: r)
                let gt = (line as NSString).range(of: ">")
                ts.addAttribute(.foregroundColor, value: accent, range: NSRange(location: r.location + gt.location, length: 1))
            }
            if t.hasPrefix("|") {
                ts.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular), range: r)
                var i = 0
                for ch in line.utf16 {
                    if ch == 124 { ts.addAttribute(.foregroundColor, value: faint, range: NSRange(location: r.location + i, length: 1)) }
                    i += 1
                }
            }
            if let m = MarkdownParser.listRe.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) {
                let mk = m.range(at: 2)
                ts.addAttributes([.foregroundColor: accent, .font: NSFont.systemFont(ofSize: size, weight: .semibold)],
                                 range: NSRange(location: r.location + mk.location, length: mk.length))
                let box = m.range(at: 3)
                if box.location != NSNotFound {
                    ts.addAttribute(.foregroundColor, value: accent, range: NSRange(location: r.location + box.location, length: box.length))
                    if (line as NSString).substring(with: box).lowercased().contains("x") {
                        let rest = NSRange(location: r.location + box.location + box.length, length: r.length - box.location - box.length)
                        ts.addAttributes([.foregroundColor: NSColor.secondaryLabelColor, .strikethroughStyle: NSUnderlineStyle.single.rawValue], range: rest)
                    }
                }
            }
        }

        // Inline: emphasis, code, links. (Inside fences this is harmless: code stays mono.)
        for m in reBold.matches(in: ts.string, range: full) {
            ts.enumerateAttribute(.font, in: m.range) { v, r, _ in
                if let f = v as? NSFont { ts.addAttribute(.font, value: font(f, adding: .bold), range: r) }
            }
            dim(ts, NSRange(location: m.range.location, length: 2))
            dim(ts, NSRange(location: NSMaxRange(m.range) - 2, length: 2))
        }
        for m in reItalic.matches(in: ts.string, range: full) {
            ts.enumerateAttribute(.font, in: m.range) { v, r, _ in
                if let f = v as? NSFont { ts.addAttribute(.font, value: font(f, adding: .italic), range: r) }
            }
            dim(ts, NSRange(location: m.range.location, length: 1))
            dim(ts, NSRange(location: NSMaxRange(m.range) - 1, length: 1))
        }
        for m in reCode.matches(in: ts.string, range: full) {
            ts.addAttributes([.font: mono, .backgroundColor: codeBg], range: m.range)
        }
        for m in reMdLink.matches(in: ts.string, range: full) {
            let target = s.substring(with: m.range(at: 2))
            let url: URL? = target.contains(":") ? URL(string: target)
                : URL(string: "holdfast-rel:" + (target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target))
            ts.addAttribute(.foregroundColor, value: faint, range: m.range)
            ts.addAttribute(.foregroundColor, value: accent, range: m.range(at: 1))
            if let url { ts.addAttribute(.link, value: url, range: m.range(at: 1)) }
        }
        for m in LinkParser.wiki.matches(in: ts.string, range: full) {
            let target = s.substring(with: m.range(at: 1))
            ts.addAttribute(.foregroundColor, value: faint, range: m.range)
            let inner = NSRange(location: m.range.location + 2, length: m.range.length - 4)
            ts.addAttribute(.foregroundColor, value: accent, range: inner)
            if let u = URL(string: "holdfast-note:" + (target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target)) {
                ts.addAttribute(.link, value: u, range: inner)
            }
        }
        for m in reTime.matches(in: ts.string, range: full) {
            ts.addAttributes([.font: mono, .foregroundColor: NSColor.secondaryLabelColor], range: m.range)
        }
        ts.endEditing()
    }

    static func dim(_ ts: NSTextStorage, _ r: NSRange) {
        ts.addAttribute(.foregroundColor, value: faint, range: r)
    }
}

/// The editor's text view: completion knows that `[[` starts a link, and
/// accepting a suggestion closes it with `]]`.
final class LinkTextView: NSTextView {
    /// True while a suggestion is being inserted (so it doesn't re-trigger itself).
    var completing = false

    /// The text typed since an unclosed `[[` on this line, if the cursor is in one.
    func wikiPartialRange() -> NSRange? {
        let sel = selectedRange()
        guard sel.length == 0 else { return nil }
        let s = string as NSString
        let line = s.lineRange(for: NSRange(location: sel.location, length: 0))
        let before = s.substring(with: NSRange(location: line.location, length: sel.location - line.location)) as NSString
        let open = before.range(of: "[[", options: .backwards)
        guard open.location != NSNotFound else { return nil }
        let typed = before.substring(from: open.location + 2)
        if typed.contains("]") || typed.contains("|") || typed.contains("[") { return nil }
        return NSRange(location: line.location + open.location + 2, length: typed.utf16.count)
    }

    override var rangeForUserCompletion: NSRange { wikiPartialRange() ?? super.rangeForUserCompletion }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        completing = true
        defer { completing = false }
        var w = word
        let accepted = movement == NSTextMovement.return.rawValue || movement == NSTextMovement.tab.rawValue
        if flag && accepted && wikiPartialRange() != nil {
            let s = string as NSString
            let after = charRange.location + charRange.length
            let closed = after + 2 <= s.length && s.substring(with: NSRange(location: after, length: 2)) == "]]"
            if !closed { w += "]]" }
        }
        super.insertCompletion(w, forPartialWordRange: charRange, movement: movement, isFinal: flag)
    }
}
