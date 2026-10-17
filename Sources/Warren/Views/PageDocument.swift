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
