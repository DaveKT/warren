import Foundation

/// One line of a Gopher menu (RFC 1436, section 3.8):
/// `<type><display>TAB<selector>TAB<host>TAB<port>[TAB<extra>]CRLF`
struct GopherItem: Identifiable, Hashable {
    let id = UUID()
    let typeChar: Character
    let display: String
    let selector: String
    let host: String
    let port: UInt16

    var type: GopherItemType? { GopherItemType(rawValue: typeChar) }

    /// The address this line points at, when it is a selectable item.
    var address: GopherAddress? {
        guard !host.isEmpty else { return nil }
        return GopherAddress(host: host, port: port, typeChar: typeChar, selector: selector)
    }

    var isSelectable: Bool {
        guard let type else { return !host.isEmpty } // unknown types: try as binary
        return type.isSelectable && !host.isEmpty
    }
}

enum GopherMenuParser {
    /// Parses a menu listing per RFC 1436. Lines are CRLF-terminated
    /// (bare LF tolerated); a line consisting of a single "." is the
    /// Lastline terminator and ends the listing.
    static func parse(_ data: Data) -> [GopherItem] {
        let text = GopherText.decode(data)
        var items: [GopherItem] = []

        // Note: "\r\n" is a single Character in Swift, so split on any
        // newline grapheme rather than on "\n".
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var line = rawLine
            if line.hasSuffix("\r") { line = line.dropLast() }
            if line == "." { break }          // Lastline: end of menu
            guard let typeChar = line.first else { continue }

            let fields = line.dropFirst().split(separator: "\t", omittingEmptySubsequences: false)
            let display = fields.count > 0 ? String(fields[0]) : ""
            let selector = fields.count > 1 ? String(fields[1]) : ""
            let host = fields.count > 2 ? String(fields[2]) : ""
            let port = fields.count > 3 ? UInt16(fields[3].trimmingCharacters(in: .whitespaces)) ?? 70 : 70

            items.append(GopherItem(typeChar: typeChar, display: display,
                                    selector: selector, host: host, port: port))
        }
        return items
    }
}

enum GopherText {
    /// Decodes server bytes as UTF-8, falling back to Latin-1 (which
    /// always succeeds) for the many legacy servers out there.
    static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Decodes a type 0 text file: strips the trailing Lastline "."
    /// and un-escapes lines beginning with ".." (RFC 1436, section 3.8).
    static func decodeTextFile(_ data: Data) -> String {
        let raw = decode(data)
        var lines: [Substring] = []
        for rawLine in raw.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var line = rawLine
            if line.hasSuffix("\r") { line = line.dropLast() }
            if line == "." { break }          // Lastline terminator
            if line.hasPrefix("..") { line = line.dropFirst() }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
