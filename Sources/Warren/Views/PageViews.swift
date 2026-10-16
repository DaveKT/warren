import SwiftUI

/// User-adjustable size for page content text, persisted in UserDefaults
/// and adjusted from the View menu (⌘+ / ⌘− / ⌘0).
enum ContentTextSize {
    static let storageKey = "contentTextSize"
    static let `default`: Double = 13
    static let range: ClosedRange<Double> = 9...24
    static let step: Double = 1
}

/// Find on Page highlighting: matches get the same moss wash as the active
/// tab, the current one the system find-indicator yellow.
enum FindHighlight {
    static let matchColor = Palette.mossWash
    static let currentColor = Color(nsColor: .findHighlightColor)

    /// The line with its matches marked, or nil when the highlights were
    /// found in different text (the page changed since the last search).
    static func line(_ line: String, highlights: LineHighlights?,
                     current: NSRange?) -> AttributedString? {
        guard let highlights, highlights.text == line else { return nil }
        var result = AttributedString()
        var cursor = line.startIndex
        for nsRange in highlights.ranges {
            guard let range = Range(nsRange, in: line), range.lowerBound >= cursor else { continue }
            result += AttributedString(String(line[cursor..<range.lowerBound]))
            var match = AttributedString(String(line[range]))
            if nsRange == current {
                match.backgroundColor = currentColor
                match.foregroundColor = .black // readable on yellow in dark mode
            } else {
                match.backgroundColor = matchColor
            }
            result += match
            cursor = range.upperBound
        }
        result += AttributedString(String(line[cursor...]))
        return result
    }
}

/// Renders a Gopher menu (type 1 / 7 results). Monospaced throughout so
/// the ASCII art that Gopherspace loves stays aligned.
struct MenuPageView: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var finder: PageFinder
    let tabID: UUID
    let items: [GopherItem]
    var memory: ScrollMemory? = nil

    var body: some View {
        let lineHighlights = finder.highlights[tabID]
        let current = finder.currentMatch.flatMap { $0.tabID == tabID ? $0 : nil }
        ScrollViewReader { proxy in
            ScrollView([.vertical]) {
                // Plain VStack (not lazy) so the full content height exists
                // immediately and Back/Forward scroll restoration can't be
                // clamped by lazily estimated layout.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        MenuRow(item: item, highlighted: FindHighlight.line(
                            item.display, highlights: lineHighlights?[index],
                            current: current?.line == index ? current?.range : nil))
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(memory)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear { reveal(with: proxy) }
            .onChange(of: finder.revealRequest) { reveal(with: proxy) }
        }
    }

    private func reveal(with proxy: ScrollViewProxy) {
        guard let match = finder.takeReveal(for: tabID), items.indices.contains(match.line) else { return }
        let rowID = items[match.line].id
        // Let a freshly shown page lay out before scrolling it.
        DispatchQueue.main.async { proxy.scrollTo(rowID, anchor: .center) }
    }
}

private struct MenuRow: View {
    @EnvironmentObject private var store: BrowserStore
    let item: GopherItem
    /// The row's text with find matches marked, when it has any.
    let highlighted: AttributedString?
    @State private var isHovering = false
    @AppStorage(ContentTextSize.storageKey) private var textSize = ContentTextSize.default

    private var label: Text {
        if let highlighted { return Text(highlighted) }
        return Text(item.display.isEmpty ? " " : item.display)
    }

    var body: some View {
        switch item.type {
        case .info:
            HStack(spacing: 8) {
                Color.clear.frame(width: 16, height: 1)
                label
                    .font(.system(size: textSize, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(.vertical, 1)
        case .error:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .frame(width: 16)
                label
                    .font(.system(size: textSize, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 1)
        default:
            linkRow
        }
    }

    private var linkRow: some View {
        Button(action: { store.open(item: item) }) {
            HStack(spacing: 8) {
                Image(systemName: item.type?.symbolName ?? "questionmark.square.dashed")
                    .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
                label
                    .font(.system(size: textSize, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .underline(isHovering)
                Text(item.type?.label ?? String(item.typeChar))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.address?.urlString ?? "")
        .contextMenu {
            if item.type == .menu || item.type == .textFile {
                Button("Open in New Tab") { store.open(item: item, inNewTab: true) }
            }
            if let address = item.address {
                Button("Copy Gopher URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address.urlString, forType: .string)
                }
                Button("Download Linked File…") {
                    store.download(address, suggestedName: item.display)
                }
            }
        }
    }
}

/// Renders a type 0 text file. The file stays one Text so a selection can
/// span lines; find scrolls to a match via an invisible marker placed
/// from the (monospaced) line height and character width.
struct TextPageView: View {
    @EnvironmentObject private var finder: PageFinder
    let tabID: UUID
    let text: String
    var memory: ScrollMemory? = nil
    @AppStorage(ContentTextSize.storageKey) private var textSize = ContentTextSize.default
    @State private var textHeight: CGFloat = 0

    private static let matchMarkerID = "find-current-match"

    var body: some View {
        let lineHighlights = finder.highlights[tabID]
        let current = finder.currentMatch.flatMap { $0.tabID == tabID ? $0 : nil }
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                content(lineHighlights, current: current)
                    .font(.system(size: textSize, design: .monospaced))
                    .textSelection(.enabled)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: TextHeightKey.self, value: geometry.size.height)
                    })
                    .overlay(alignment: .topLeading) {
                        if let current { matchMarker(for: current, lineHighlights) }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(memory)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onPreferenceChange(TextHeightKey.self) { textHeight = $0 }
            .onAppear { reveal(with: proxy) }
            .onChange(of: finder.revealRequest) { reveal(with: proxy) }
            // A new page can't place the marker until its text is measured.
            .onChange(of: textHeight) { reveal(with: proxy) }
        }
    }

    /// SwiftUI's Text slows sharply with thousands of attributed runs (a
    /// single-letter search on a long file can stall the UI for seconds),
    /// so past this many matches only the lines around the current match
    /// are highlighted; the count and ⌘G navigation still cover them all.
    private static let fullHighlightLimit = 500
    private static let highlightWindow = 100

    private func content(_ lineHighlights: [Int: LineHighlights]?,
                         current: FindMatch?) -> Text {
        guard let lineHighlights else { return Text(text) }
        let matchCount = lineHighlights.values.reduce(0) { $0 + $1.ranges.count }
        let window: ClosedRange<Int>? = matchCount > Self.fullHighlightLimit
            ? (current?.line ?? 0).advanced(by: -Self.highlightWindow)...(current?.line ?? 0).advanced(by: Self.highlightWindow)
            : nil
        // Plain stretches stay String-backed Text (SwiftUI renders a whole
        // page as one AttributedString an order of magnitude slower, even
        // with few runs); only highlighted lines are spliced in attributed.
        var result = Text("")
        var plain = ""
        for (index, line) in TabContent.text(text).findableLines.enumerated() {
            if index > 0 { plain += "\n" }
            if let window, !window.contains(index) {
                plain += line
                continue
            }
            guard let highlighted = FindHighlight.line(
                line, highlights: lineHighlights[index],
                current: current?.line == index ? current?.range : nil) else {
                plain += line
                continue
            }
            result = result + Text(plain) + Text(highlighted)
            plain = ""
        }
        return result + Text(plain)
    }

    @ViewBuilder
    private func matchMarker(for match: FindMatch,
                             _ lineHighlights: [Int: LineHighlights]?) -> some View {
        let lines = TabContent.text(text).findableLines
        let lineHeight = textHeight / CGFloat(lines.count)
        if lineHeight > 0, lines.indices.contains(match.line),
           lineHighlights?[match.line]?.text == lines[match.line],
           let range = Range(match.range, in: lines[match.line]) {
            let line = lines[match.line]
            let font = NSFont.monospacedSystemFont(ofSize: textSize, weight: .regular)
            let charWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
            let column = line.distance(from: line.startIndex, to: range.lowerBound)
            let length = line.distance(from: range.lowerBound, to: range.upperBound)
            Color.clear
                .frame(width: max(charWidth * CGFloat(length), 1), height: lineHeight)
                .id(Self.matchMarkerID)
                .padding(.leading, charWidth * CGFloat(column))
                .padding(.top, lineHeight * CGFloat(match.line))
        }
    }

    private func reveal(with proxy: ScrollViewProxy) {
        guard textHeight > 0, finder.takeReveal(for: tabID) != nil else { return }
        // The marker moves in the same update; scroll once it's laid out.
        DispatchQueue.main.async { proxy.scrollTo(Self.matchMarkerID, anchor: .center) }
    }
}

private struct TextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Renders inline images (types g, I, p).
struct ImagePageView: View {
    let data: Data
    var memory: ScrollMemory? = nil

    var body: some View {
        if let image = NSImage(data: data) {
            ScrollView([.vertical, .horizontal]) {
                Image(nsImage: image)
                    .padding(16)
                    .background(memory)
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            ContentUnavailableView("Couldn't decode this image",
                                   systemImage: "photo.badge.exclamationmark")
        }
    }
}

/// The search prompt shown for type 7 (index-search) and type 2 (CSO) items.
struct SearchPromptView: View {
    @EnvironmentObject private var store: BrowserStore
    let prompt: SearchPrompt
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(prompt.itemTitle, systemImage: "magnifyingglass")
                .font(.headline)
            Text("\(prompt.address.host) is asking for search words.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Search words", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel") { store.searchPrompt = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Search", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.submitSearch(query: trimmed)
    }
}
