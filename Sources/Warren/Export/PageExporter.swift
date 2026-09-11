import AppKit
import Foundation
import UniformTypeIdentifiers

enum ExportFormat {
    case plainText
    case markdown

    var fileExtension: String {
        switch self {
        case .plainText: return "txt"
        case .markdown: return "md"
        }
    }

    var contentType: UTType {
        switch self {
        case .plainText: return .plainText
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        }
    }
}

@MainActor
enum PageExporter {
    /// Renders the current page and presents a save panel.
    static func export(tab: BrowserTab, format: ExportFormat) {
        guard let rendered = render(content: tab.content, title: tab.title,
                                    address: tab.currentAddress, format: format) else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName(for: tab, format: format)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? rendered.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static func canExport(_ content: TabContent) -> Bool {
        switch content {
        case .menu, .text: return true
        default: return false
        }
    }

    static func render(content: TabContent, title: String,
                       address: GopherAddress?, format: ExportFormat) -> String? {
        switch (content, format) {
        case (.text(let body), .plainText):
            return body
        case (.text(let body), .markdown):
            return markdownHeader(title: title, address: address)
                + "```\n" + body.replacingOccurrences(of: "```", with: "`\u{200B}``") + "\n```\n"
        case (.menu(let items), .plainText):
            return menuAsPlainText(items, title: title, address: address)
        case (.menu(let items), .markdown):
            return menuAsMarkdown(items, title: title, address: address)
        default:
            return nil
        }
    }

    private static func markdownHeader(title: String, address: GopherAddress?) -> String {
        var s = "# \(title)\n\n"
        if let address {
            s += "Source: <\(address.urlString)>\n\n"
        }
        return s
    }

    private static func menuAsPlainText(_ items: [GopherItem], title: String,
                                        address: GopherAddress?) -> String {
        var lines: [String] = [title]
        if let address { lines.append(address.urlString) }
        lines.append(String(repeating: "-", count: 40))
        for item in items {
            switch item.type {
            case .info:
                lines.append(stripIcons(item.display))
            default:
                let display = stripIcons(item.display).trimmingCharacters(in: .whitespaces)
                var line = "[\(item.type?.label ?? String(item.typeChar))] \(display)"
                if let target = linkTarget(for: item) { line += "  <\(target)>" }
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Markdown rendering of a menu. Info lines are treated as prose by
    /// default; only lines that look like ASCII art keep code-indent, a
    /// rule line (`‾‾‾` etc.) under a line italicizes it, and `* ` runs
    /// become real markdown bullets.
    private static func menuAsMarkdown(_ items: [GopherItem], title: String,
                                       address: GopherAddress?) -> String {
        var out: [String] = []
        var pendingBlank = false
        var seenBody = false

        func append(_ line: String, isArt: Bool = false) {
            let lastIsArt = out.last?.hasPrefix("    ") ?? false
            // Art blocks need a blank line on both sides to stay code blocks.
            if pendingBlank || (!out.isEmpty && isArt != lastIsArt && !(out.last?.isEmpty ?? true)) {
                out.append("")
            }
            pendingBlank = false
            out.append(line)
            seenBody = true
        }

        for item in items {
            switch item.type {
            case .info:
                let raw = stripIcons(item.display)
                let text = trimTrailing(raw)
                if text.trimmingCharacters(in: .whitespaces).isEmpty {
                    if !out.isEmpty { pendingBlank = true }
                    continue
                }
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                if isRuleLine(trimmed) {
                    // A rule under a prose line is an underline: italicize
                    // the line above and drop the rule itself.
                    if let last = out.last, !last.isEmpty, !last.hasPrefix("    "),
                       !last.hasPrefix("*"), !pendingBlank {
                        out[out.count - 1] = "*\(last)*"
                        pendingBlank = true // keep the heading its own paragraph
                    } else if seenBody {
                        append("---")
                    }
                    continue
                }
                if !seenBody, trimmed == title.trimmingCharacters(in: .whitespaces) {
                    continue // page repeats its own title; the # header has it
                }
                if let bullet = bulletText(text) {
                    append("- \(bullet)")
                } else if isArtLine(text) {
                    append("    \(raw)", isArt: true)
                } else {
                    append(escapeProse(trimmed))
                }
            case .error:
                append("> ⚠️ \(escapeMarkdown(stripIcons(item.display)))")
            default:
                let display = stripIcons(item.display).trimmingCharacters(in: .whitespaces)
                let label = escapeMarkdown(display.isEmpty ? "link" : display)
                if let target = linkTarget(for: item) {
                    append("- [\(label)](\(target)) *(\(item.type?.label ?? String(item.typeChar)))*")
                } else {
                    append("- \(label)")
                }
            }
        }
        return markdownHeader(title: title, address: address)
            + out.joined(separator: "\n") + "\n"
    }

    /// The URL a menu item should link to. Type h items carrying a
    /// `URL:` selector link to the real target, not a synthetic gopher URL.
    private static func linkTarget(for item: GopherItem) -> String? {
        if item.type == .html, item.selector.uppercased().hasPrefix("URL:") {
            let raw = String(item.selector.dropFirst(4))
            if let url = URL(string: raw), url.scheme != nil { return raw }
        }
        return item.address?.urlString
    }

    /// Removes Private Use Area glyphs (Nerd Font icons and the like)
    /// that some servers put in display strings.
    private static func stripIcons(_ s: String) -> String {
        let stripped = s.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0xE000...0xF8FF, 0xF0000...0xFFFFD, 0x100000...0x10FFFD:
                return false
            default:
                return true
            }
        }
        return String(String.UnicodeScalarView(stripped))
    }

    private static let ruleCharacters = Set("‾¯─━═‗_~–—⎯⎻⎼⎽=-")

    /// True for a line made entirely of underline/rule characters.
    private static func isRuleLine(_ s: String) -> Bool {
        s.count >= 2 && s.allSatisfy { ruleCharacters.contains($0) }
    }

    /// Extracts bullet text from lines like ` * keep the weird menus`.
    private static func bulletText(_ s: String) -> String? {
        var rest = Substring(s)
        let leadingSpaces = rest.prefix(while: { $0 == " " }).count
        guard leadingSpaces <= 3 else { return nil } // deeper indent: art
        rest = rest.drop(while: { $0 == " " })
        guard let marker = rest.first, "*•‣▪◦·-".contains(marker) else { return nil }
        rest = rest.dropFirst()
        guard rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    /// Heuristic for lines that are ASCII art / alignment-sensitive
    /// rather than prose: box-drawing characters, long runs of a symbol,
    /// or deep indentation.
    private static func isArtLine(_ s: String) -> Bool {
        if s.prefix(while: { $0 == " " }).count >= 4 { return true }
        var runChar: Character = " "
        var runLength = 0
        var symbols = 0
        var nonSpace = 0
        for ch in s {
            if let scalar = ch.unicodeScalars.first,
               (0x2500...0x25FF).contains(scalar.value) { return true } // box drawing
            if ch == runChar { runLength += 1 } else { runChar = ch; runLength = 1 }
            if runLength >= 4, !ch.isLetter, !ch.isNumber, ch != " ", ch != "." {
                return true
            }
            if ch != " " {
                nonSpace += 1
                if !ch.isLetter, !ch.isNumber { symbols += 1 }
            }
        }
        // Mostly punctuation/symbols with little text: figure art, not prose.
        return nonSpace >= 3 && Double(symbols) / Double(nonSpace) >= 0.6
    }

    /// Prose needs only light escaping: stop a leading character from
    /// turning the line into a markdown block element.
    private static func escapeProse(_ s: String) -> String {
        if let first = s.first, "#>+".contains(first) {
            return "\\" + s
        }
        return s
    }

    private static func trimTrailing(_ s: String) -> String {
        var sub = Substring(s)
        while let last = sub.last, last == " " || last == "\t" { sub = sub.dropLast() }
        return String(sub)
    }

    private static func escapeMarkdown(_ s: String) -> String {
        var out = ""
        for ch in s {
            if "\\`*_[]<>#".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    private static func suggestedName(for tab: BrowserTab, format: ExportFormat) -> String {
        var base = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = "gopher-page" }
        base = base.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "\(base).\(format.fileExtension)"
    }
}
