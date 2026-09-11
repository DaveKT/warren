import Foundation

/// A fully qualified location in Gopherspace: host, port, item type,
/// selector string, and (for type 7 items) an optional search query.
/// URL form follows RFC 4266 ("The gopher URI Scheme").
struct GopherAddress: Hashable {
    var host: String
    var port: UInt16 = 70
    var typeChar: Character = "1"
    var selector: String = ""
    var searchQuery: String? = nil

    var type: GopherItemType? { GopherItemType(rawValue: typeChar) }

    /// Canonical gopher:// URL string (RFC 4266). The selector is
    /// percent-encoded; a search query is appended after an encoded tab (%09).
    var urlString: String {
        var s = "gopher://\(host)"
        if port != 70 { s += ":\(port)" }
        s += "/\(typeChar)\(Self.encodeSelector(selector))"
        if let q = searchQuery, !q.isEmpty {
            s += "%09\(Self.encodeSelector(q))"
        }
        return s
    }

    /// Human-friendly display string for the address bar.
    var displayString: String { urlString }

    private static func encodeSelector(_ s: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "%\t?#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// Parses user input: a gopher:// URL, a bare host, `host:port`, or
    /// `host/1/some/selector`. Returns nil for input with no usable host.
    static func parse(_ input: String) -> GopherAddress? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let range = text.range(of: "gopher://", options: [.caseInsensitive, .anchored]) {
            text = String(text[range.upperBound...])
        } else if text.contains("://") {
            return nil // some other scheme; not ours
        }

        // Split authority from path.
        var authority = text
        var path = ""
        if let slash = text.firstIndex(of: "/") {
            authority = String(text[..<slash])
            path = String(text[text.index(after: slash)...])
        }
        guard !authority.isEmpty else { return nil }

        var host = authority
        var port: UInt16 = 70
        // IPv6 literal in brackets, or host[:port]
        if authority.hasPrefix("[") {
            if let close = authority.firstIndex(of: "]") {
                host = String(authority[authority.index(after: authority.startIndex)..<close])
                let rest = authority[authority.index(after: close)...]
                if rest.hasPrefix(":"), let p = UInt16(rest.dropFirst()) { port = p }
            }
        } else if let colon = authority.lastIndex(of: ":") {
            let portPart = authority[authority.index(after: colon)...]
            if let p = UInt16(portPart) {
                host = String(authority[..<colon])
                port = p
            }
        }
        guard !host.isEmpty else { return nil }

        var address = GopherAddress(host: host, port: port)
        guard !path.isEmpty else { return address } // default: type 1, empty selector

        // First character of the path is the gopher item type.
        address.typeChar = path.first!
        var rawSelector = String(path.dropFirst())

        // Percent-encoded tab separates selector from search query (RFC 4266).
        if let tabRange = rawSelector.range(of: "%09", options: .caseInsensitive) {
            address.searchQuery = String(rawSelector[tabRange.upperBound...]).removingPercentEncoding
            rawSelector = String(rawSelector[..<tabRange.lowerBound])
        } else if let tab = rawSelector.firstIndex(of: "\t") {
            address.searchQuery = String(rawSelector[rawSelector.index(after: tab)...])
            rawSelector = String(rawSelector[..<tab])
        }
        address.selector = rawSelector.removingPercentEncoding ?? rawSelector
        return address
    }
}
