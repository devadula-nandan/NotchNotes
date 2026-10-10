import Foundation

public enum ListKind { case checkbox, numbered }

// List editing on plain text: "- [ ] item", "1. item" and "- item" lines
public enum ListText {
    // "- [ ] item" / "- [x] item", also "- []", "-[ ]" and "*" / "+" markers:
    // group 1 = "- [ ]", 2 = mark, 3 = text
    public static let checkboxRegex = try! NSRegularExpression(pattern: "^[ \\t]*([-*+] ?\\[([ xX]?)\\])(.*)$",
                                                               options: .anchorsMatchLines)
    // "1. item": group 1 = indent, 2 = number, 3 = text
    public static let numberedRegex = try! NSRegularExpression(pattern: "^([ \\t]*)(\\d+)\\. (.*)$")
    // "- item" (also "*" / "+"): group 1 = indent, 2 = marker, 3 = text. Also matches checkbox lines, so test those first
    public static let bulletRegex = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+]) (.*)$")
    private static let listPrefixRegex = try! NSRegularExpression(pattern: "^(?:[-*+] ?\\[[ xX]?\\] ?|[-*+] |\\d+\\. )")

    public static let indentUnit = "  "

    private static func isIndent(_ c: Character) -> Bool { c == " " || c == "\t" }

    // A block of whole lines, split up; `trailing` is true when the block ends with a line break
    private static func split(_ block: String) -> (lines: [String], trailing: Bool) {
        let trailing = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if trailing { lines.removeLast() }
        return (lines, trailing)
    }

    private static func isListLine(_ line: String) -> Bool {
        let range = NSRange(location: 0, length: (line as NSString).length)
        return [checkboxRegex, numberedRegex, bulletRegex].contains { $0.firstMatch(in: line, range: range) != nil }
    }

    // Toggle "- [ ] " or "1. " on a block of whole lines. `removing` is true when the list was taken off
    public static func toggled(_ block: String, kind: ListKind) -> (text: String, removing: Bool) {
        struct Line { var indent: String; var prefix: String; var body: String; var kind: ListKind? }

        let (raw, trailing) = split(block)
        let lines: [Line] = raw.map { line in
            let indent = String(line.prefix(while: isIndent))
            let rest = String(line.dropFirst(indent.count)) as NSString
            let n = listPrefixRegex.firstMatch(in: rest as String, range: NSRange(location: 0, length: rest.length))?.range.length ?? 0
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
        if trailing { replacement += "\n" }
        return (replacement, removing)
    }

    // Keeps a numbered list sequential: the numbers to change in the items that follow the line at `location`.
    // Ranges are in `string` as it is now, in ascending order, so apply them last one first
    public static func renumbering(_ string: String, after location: Int) -> [(range: NSRange, number: String)] {
        let text = string as NSString
        func contents(at location: Int) -> NSRange {
            var start = 0, end = 0
            text.getLineStart(&start, end: nil, contentsEnd: &end, for: NSRange(location: location, length: 0))
            return NSRange(location: start, length: end - start)
        }

        let first = contents(at: min(location, text.length))
        guard let m = numberedRegex.firstMatch(in: string, range: first),
              var number = Int(text.substring(with: m.range(at: 2))) else { return [] }
        let indent = text.substring(with: m.range(at: 1))

        var edits: [(range: NSRange, number: String)] = []
        var pos = NSMaxRange(text.lineRange(for: first))
        while pos < text.length {
            let item = contents(at: pos)
            guard let lm = numberedRegex.firstMatch(in: string, range: item),
                  text.substring(with: lm.range(at: 1)) == indent else { break }
            number += 1
            let old = lm.range(at: 2), new = "\(number)"
            if text.substring(with: old) != new { edits.append((old, new)) }
            pos = NSMaxRange(text.lineRange(for: item))
        }
        return edits
    }

    // One checklist: checkbox lines right under one another at the same indent
    private static let checklistRegex = try! NSRegularExpression(
        pattern: "^([ \\t]*)[-*+] ?\\[[ xX]?\\].*(?:\\n\\1[-*+] ?\\[[ xX]?\\].*)*$", options: .anchorsMatchLines)

    // The checklist around `location` with its checked items moved below the unchecked ones: the range to replace
    // and the text to put there. nil when it is already in order
    public static func checkedLast(_ string: String, at location: Int) -> (range: NSRange, text: String)? {
        guard let list = checklistRegex.matches(in: string, range: NSRange(location: 0, length: string.utf16.count))
            .first(where: { NSLocationInRange(location, $0.range) })?.range else { return nil }
        let lines = (string as NSString).substring(with: list).components(separatedBy: "\n")
        // The mark is what sits right before the first "]"
        func checked(_ line: String) -> Bool { line.prefix { $0 != "]" }.last?.lowercased() == "x" }
        let sorted = lines.filter { !checked($0) } + lines.filter(checked)
        return sorted == lines ? nil : (list, sorted.joined(separator: "\n"))
    }

    // Tab / Shift-Tab on a block of whole lines: its list items move one level in or out.
    // nil when the block has no list items, so Tab keeps its usual meaning there
    public static func indented(_ block: String, outdent: Bool) -> String? {
        let (lines, trailing) = split(block)
        guard lines.contains(where: isListLine) else { return nil }
        var result = lines.map { line -> String in
            guard isListLine(line) else { return line }
            guard outdent else { return indentUnit + line }
            if line.hasPrefix("\t") { return String(line.dropFirst()) }
            return String(line.dropFirst(min(line.prefix { $0 == " " }.count, indentUnit.count)))
        }.joined(separator: "\n")
        if trailing { result += "\n" }
        return result
    }

    // The whole lines to restyle after `length` characters were put in at `location`. One character either
    // side is included: an edit can join or split lines, which changes what its neighbours are
    public static func restyleRange(in text: NSString, editedAt location: Int, length: Int) -> NSRange {
        let start = max(min(location, text.length) - 1, 0), end = min(location + length + 1, text.length)
        return text.lineRange(for: NSRange(location: start, length: max(end - start, 0)))
    }
}
