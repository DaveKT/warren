import Foundation

/// A page's text as one document for `PageTextView`: its find lines joined
/// by "\n", plus the UTF-16 offset where each line starts, so find matches
/// (a line and a range within it) map onto document ranges.
struct PageDocument {
    let lines: [String]
    let string: String
    /// UTF-16 offset of each line's first character in `string`.
    let lineStarts: [Int]
    /// The menu items, one per line; empty for text pages.
    let items: [GopherItem]
    /// Per line: whether it's a menu info line that reads as prose, and so
    /// may be rejoined with its neighbours when copied.
    private let isProse: [Bool]
    /// A prose line at least this long (trimmed) was wrapped by its author
    /// and continues on the next line; shorter ones ended deliberately.
    private let wrapThreshold: Int

    init(content: TabContent) {
        lines = content.findableLines
        if case .menu(let items) = content {
            self.items = items
        } else {
            items = []
        }
        string = lines.joined(separator: "\n")
        var starts: [Int] = []
        starts.reserveCapacity(lines.count)
        var offset = 0
        for line in lines {
            starts.append(offset)
            offset += line.utf16.count + 1
        }
        lineStarts = starts

        let prose = zip(lines, items).map { line, item in item.type == .info && Self.readsAsProse(line) }
        isProse = prose
        let longest = zip(lines, prose).filter(\.1).map { $0.0.trimmingCharacters(in: .whitespaces).count }.max() ?? 0
        wrapThreshold = max(20, longest * 6 / 10)
    }

    var length: Int { (string as NSString).length }

    /// The document range of one line, without its trailing newline.
    func range(ofLine line: Int) -> NSRange {
        NSRange(location: lineStarts[line], length: lines[line].utf16.count)
    }

    /// The line containing a document offset (a newline counts toward the
    /// line it ends).
    func line(at offset: Int) -> Int? {
        guard !lineStarts.isEmpty, offset >= 0 else { return nil }
        var low = 0, high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    // MARK: Copying

    /// The text to copy for a selection. Menus send prose as hard-wrapped
    /// info lines, so lines that continue a paragraph are rejoined with a
    /// space; blank lines (paragraph breaks), links, and anything laid out
    /// deliberately (ASCII art, columns, lists, short lines) keep their
    /// breaks. Text-file pages copy exactly as shown.
    func copyText(for range: NSRange) -> String {
        let text = string as NSString
        let range = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard !items.isEmpty, range.length > 0,
              let first = line(at: range.location),
              let last = line(at: NSMaxRange(range) - 1) else {
            return text.substring(with: range)
        }

        var output = ""
        var joinable = false
        for index in first...last {
            let piece = text.substring(with: NSIntersectionRange(self.range(ofLine: index), range))
            let isBlank = lines[index].trimmingCharacters(in: .whitespaces).isEmpty
            if index > first {
                if joinable, isProse[index], indent(of: index) <= indent(of: index - 1) {
                    output = Self.trimmingTrailingWhitespace(output)
                    let continuation = String(piece.drop(while: { $0 == " " || $0 == "\t" }))
                    // A word hyphenated across the break stays joined.
                    if let end = output.last, end == "-", output.dropLast().last?.isLetter == true {
                        output += continuation
                    } else {
                        output += " " + continuation
                    }
                    joinable = isProse[index] && wrapsToNextLine(index)
                    continue
                }
                output += "\n"
            }
            output += isBlank ? "" : Self.trimmingTrailingWhitespace(piece)
            joinable = isProse[index] && wrapsToNextLine(index)
        }
        // A selection that runs through the final line break keeps it.
        if NSMaxRange(range) > NSMaxRange(self.range(ofLine: last)) { output += "\n" }
        return output
    }

    private func wrapsToNextLine(_ index: Int) -> Bool {
        lines[index].trimmingCharacters(in: .whitespaces).count >= wrapThreshold
    }

    private func indent(of index: Int) -> Int {
        lines[index].prefix(while: { $0 == " " || $0 == "\t" }).count
    }

    /// Mostly letters, no column-aligning runs of spaces, not a list item.
    private static func readsAsProse(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.contains("   "),
              trimmed.range(of: #"^([-*+•]|\d+[.)])\s"#, options: .regularExpression) == nil
        else { return false }
        let visible = trimmed.filter { !$0.isWhitespace }
        let letters = visible.filter(\.isLetter).count
        return letters * 2 >= visible.count
    }

    private static func trimmingTrailingWhitespace(_ text: String) -> String {
        var text = text
        while let last = text.last, last == " " || last == "\t" { text.removeLast() }
        return text
    }

    /// Document ranges for a page's find highlights, plus the current
    /// match's. Lines whose text differs from what the search saw (the
    /// page changed since) and ranges that don't fit are skipped.
    func highlightRanges(_ highlights: [Int: LineHighlights]?,
                         current: FindMatch?) -> (all: [NSRange], current: NSRange?) {
        guard let highlights else { return ([], nil) }
        var all: [NSRange] = []
        var currentRange: NSRange?
        for (line, lineHighlights) in highlights {
            guard lines.indices.contains(line), lines[line] == lineHighlights.text else { continue }
            let lineLength = lines[line].utf16.count
            for range in lineHighlights.ranges
            where range.location >= 0 && range.length > 0 && NSMaxRange(range) <= lineLength {
                let documentRange = NSRange(location: lineStarts[line] + range.location, length: range.length)
                all.append(documentRange)
                if current?.line == line, current?.range == range {
                    currentRange = documentRange
                }
            }
        }
        return (all, currentRange)
    }
}
