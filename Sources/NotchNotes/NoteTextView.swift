import Cocoa

// Notes editor: placeholder, checkboxes drawn over "- [ ]", numbered lists
final class NoteTextView: ArrowTextView {
    enum ListKind { case checkbox, numbered }

    var onChange: (() -> Void)?
    private var boxes: [(range: NSRange, mark: NSRange, checked: Bool)] = []

    // "- [ ] item" / "- [x] item", also "- []", "-[ ]" and "*" / "+" markers:
    // group 1 = "- [ ]", 2 = mark, 3 = text
    private static let checkboxRegex = try! NSRegularExpression(pattern: "^[ \\t]*([-*+] ?\\[([ xX]?)\\])(.*)$",
                                                                options: .anchorsMatchLines)
    // "1. item": group 1 = indent, 2 = number, 3 = text
    private static let numberedRegex = try! NSRegularExpression(pattern: "^([ \\t]*)(\\d+)\\. (.*)$")
    private static let listPrefixRegex = try! NSRegularExpression(pattern: "^(?:[-*+] ?\\[[ xX]?\\] ?|[-*+] |\\d+\\. )")

    private var text: NSString { string as NSString }
    private var baseFont: NSFont { font ?? .monospacedSystemFont(ofSize: 13, weight: .regular) }
    private var baseAttrs: [NSAttributedString.Key: Any] { [.font: baseFont, .foregroundColor: inkColor] }

    // MARK: - Text helpers

    // The line containing `location`, without its line break
    private func lineRange(at location: Int) -> NSRange {
        var start = 0, contentsEnd = 0
        text.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        return NSRange(location: start, length: contentsEnd - start)
    }

    private func isBlank(_ range: NSRange) -> Bool {
        text.substring(with: range).trimmingCharacters(in: .whitespaces).isEmpty
    }

    // An undoable edit; optionally leaves the caret at `caret`
    @discardableResult
    private func replace(_ range: NSRange, with replacement: String, caret: Int? = nil) -> Bool {
        guard shouldChangeText(in: range, replacementString: replacement) else { return false }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        if let caret { setSelectedRange(NSRange(location: caret, length: 0)) }
        return true
    }

    override func didChangeText() {
        restyle()
        super.didChangeText()
        onChange?()
    }

    // MARK: - Styling and drawing

    // Sit the text close under the toolbar; the rest of the vertical inset goes below the text
    override var textContainerOrigin: NSPoint { NSPoint(x: textContainerInset.width, y: 2) }

    // Hide "- [ ]" (a checkbox is drawn over it) and dim checked items
    func restyle() {
        guard let ts = textStorage else { return }
        let full = NSRange(location: 0, length: ts.length)
        let charW = ("0" as NSString).size(withAttributes: baseAttrs).width
        boxes = []
        ts.beginEditing()
        ts.setAttributes(baseAttrs, range: full)
        Self.checkboxRegex.enumerateMatches(in: ts.string, range: full) { m, _, _ in
            guard let m else { return }
            let prefix = m.range(at: 1), body = m.range(at: 3)
            let checked = !isBlank(m.range(at: 2))
            boxes.append((prefix, m.range(at: 2), checked))
            ts.addAttribute(.foregroundColor, value: NSColor.clear, range: prefix)
            // Squeeze the hidden "- [ ]" down to the width of the drawn box
            let squeeze = (CGFloat(prefix.length) * charW - baseFont.pointSize) / CGFloat(prefix.length - 1)
            ts.addAttribute(.kern, value: -squeeze, range: NSRange(location: prefix.location, length: prefix.length - 1))
            if checked {
                // Strike only the words, not the spaces around them
                let words = text.substring(with: body)
                let lead = words.prefix { $0 == " " || $0 == "\t" }.utf16.count
                let length = (words.trimmingCharacters(in: .whitespaces) as NSString).length
                ts.addAttributes([.foregroundColor: NSColor(white: 0.3, alpha: 1),
                                  .strikethroughColor: NSColor(white: 0.45, alpha: 1),
                                  .strikethroughStyle: NSUnderlineStyle.single.rawValue],
                                 range: NSRange(location: body.location + lead, length: length))
            }
        }
        ts.endEditing()
        typingAttributes = baseAttrs
        needsDisplay = true
    }

    private func boxRect(for range: NSRange) -> CGRect {
        guard let lm = layoutManager, let tc = textContainer else { return .zero }
        let r = lm.boundingRect(forGlyphRange: lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil), in: tc)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let s = baseFont.pointSize
        return CGRect(x: r.minX + (r.width - s) / 2, y: r.midY - s / 2, width: s, height: s)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        for box in boxes {
            let rect = boxRect(for: box.range)
            guard rect.intersects(dirtyRect) else { continue }
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            if box.checked {
                // Same look as the active checklist button: soft green wash, solid green tick
                NSColor.systemGreen.withAlphaComponent(0.24).setFill()
                path.fill()
                let check = NSBezierPath()
                check.move(to: NSPoint(x: rect.minX + rect.width * 0.23, y: rect.midY))
                check.line(to: NSPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.27))
                check.line(to: NSPoint(x: rect.maxX - rect.width * 0.23, y: rect.minY + rect.height * 0.27))
                check.lineWidth = 1.6
                check.lineCapStyle = .round
                NSColor.systemGreen.setStroke()
                check.stroke()
            } else {
                path.lineWidth = 1.2
                NSColor(white: 0.55, alpha: 1).setStroke()
                path.stroke()
            }
        }

        if string.isEmpty {
            let x = textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0)
            "Type your notes here...".draw(at: NSPoint(x: x, y: textContainerOrigin.y), withAttributes: [
                .foregroundColor: NSColor(white: 0.5, alpha: 1), .font: baseFont,
            ])
        }
    }

    // MARK: - Lists

    var listKindAtCaret: ListKind? {
        let line = lineRange(at: selectedRange().location)
        if Self.checkboxRegex.firstMatch(in: string, range: line) != nil { return .checkbox }
        if Self.numberedRegex.firstMatch(in: string, range: line) != nil { return .numbered }
        return nil
    }

    // Toggle "- [ ] " or "1. " on the current / selected lines
    func toggleList(_ kind: ListKind) {
        struct Line { var indent: String; var prefix: String; var body: String; var kind: ListKind? }

        let range = text.lineRange(for: selectedRange())
        let block = text.substring(with: range)
        let trailingNewline = block.hasSuffix("\n")
        var raw = block.components(separatedBy: "\n")
        if trailingNewline { raw.removeLast() }

        let lines: [Line] = raw.map { line in
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let rest = String(line.dropFirst(indent.count)) as NSString
            let n = Self.listPrefixRegex.firstMatch(in: rest as String, range: NSRange(location: 0, length: rest.length))?.range.length ?? 0
            let prefix = rest.substring(to: n)
            return Line(indent: indent, prefix: prefix, body: rest.substring(from: n),
                        kind: prefix.contains("[") ? .checkbox : prefix.first?.isNumber == true ? .numbered : nil)
        }

        // All the non-blank lines already are this kind of list: take it off instead
        let content = lines.filter { !($0.prefix + $0.body).trimmingCharacters(in: .whitespaces).isEmpty }
        let removing = !content.isEmpty && content.allSatisfy { $0.kind == kind }

        var number = 0
        var replacement = lines.map { l -> String in
            let blank = l.prefix.isEmpty && l.body.trimmingCharacters(in: .whitespaces).isEmpty
            if removing || (blank && lines.count > 1) { return l.indent + l.body }
            number += 1
            return l.indent + (kind == .checkbox ? "- [ ] " : "\(number). ") + l.body
        }.joined(separator: "\n")
        if trailingNewline { replacement += "\n" }

        let end = range.location + (replacement as NSString).length - (trailingNewline ? 1 : 0)
        if replace(range, with: replacement, caret: end), kind == .numbered, !removing { renumber(after: end) }
    }

    // Keep a numbered list sequential: renumber the items that follow the line at `location`
    private func renumber(after location: Int) {
        let first = lineRange(at: min(location, text.length))
        guard let m = Self.numberedRegex.firstMatch(in: string, range: first),
              var number = Int(text.substring(with: m.range(at: 2))) else { return }
        let indent = text.substring(with: m.range(at: 1))
        let caret = selectedRange()

        var pos = NSMaxRange(text.lineRange(for: first))
        while pos < text.length {
            let item = lineRange(at: pos)
            guard let lm = Self.numberedRegex.firstMatch(in: string, range: item),
                  text.substring(with: lm.range(at: 1)) == indent else { break }
            number += 1
            let old = lm.range(at: 2), new = "\(number)"
            if text.substring(with: old) != new, shouldChangeText(in: old, replacementString: new) {
                textStorage?.replaceCharacters(in: old, with: new)
            }
            pos = NSMaxRange(text.lineRange(for: lineRange(at: pos)))
        }
        didChangeText()
        setSelectedRange(caret)
    }

    // MARK: - Editing

    // Click a checkbox to toggle it
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let box = boxes.first(where: { boxRect(for: $0.range).insetBy(dx: -4, dy: -4).contains(p) }) {
            replace(box.mark, with: box.checked ? " " : "x")
        } else {
            super.mouseDown(with: event)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Backspace with the caret inside or right after a list marker removes it in one go:
    // a number is cleared from its line, a checkbox takes its whole line with it
    override func deleteBackward(_ sender: Any?) {
        let sel = selectedRange(), line = lineRange(at: sel.location)
        guard sel.length == 0 else { return super.deleteBackward(sender) }

        if let n = Self.numberedRegex.firstMatch(in: string, range: line) {
            let marker = NSRange(location: n.range(at: 2).location, length: n.range(at: 3).location - n.range(at: 2).location)
            if sel.location > marker.location, sel.location <= NSMaxRange(marker) {
                replace(marker, with: "", caret: marker.location)
                return
            }
        }

        if let m = Self.checkboxRegex.firstMatch(in: string, range: line) {
            let prefix = m.range(at: 1)
            var textStart = NSMaxRange(prefix)
            if textStart < text.length, text.character(at: textStart) == 32 { textStart += 1 }
            if sel.location > prefix.location, sel.location <= textStart {
                // Take the preceding line break so the caret lands at the end of the previous line
                let range = line.location > 0 ? NSRange(location: line.location - 1, length: line.length + 1)
                                              : text.lineRange(for: line)
                replace(range, with: "", caret: range.location)
                return
            }
        }

        super.deleteBackward(sender)
    }

    // Enter on a list line continues the list; Enter on an empty item ends it
    override func insertNewline(_ sender: Any?) {
        let sel = selectedRange(), line = lineRange(at: sel.location)
        let indent: String, body: NSRange, next: String
        if let n = Self.numberedRegex.firstMatch(in: string, range: line) {
            indent = text.substring(with: n.range(at: 1))
            body = n.range(at: 3)
            next = "\((Int(text.substring(with: n.range(at: 2))) ?? 0) + 1). "
        } else if let m = Self.checkboxRegex.firstMatch(in: string, range: line) {
            indent = text.substring(with: NSRange(location: line.location, length: m.range(at: 1).location - line.location))
            body = m.range(at: 3)
            next = "- [ ] "
        } else {
            return super.insertNewline(sender)
        }

        if isBlank(body) {
            insertText(indent, replacementRange: line)
        } else {
            insertText("\n" + indent + next, replacementRange: sel)
            renumber(after: selectedRange().location)   // does nothing on a checkbox line
        }
    }
}
