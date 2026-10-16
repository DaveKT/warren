import Combine
import Foundation

/// One occurrence of the find query: a range within one line of a tab's
/// page (a menu row, or a line of a text file). The range is in UTF-16
/// offsets, valid only for the line text it was found in.
struct FindMatch: Equatable {
    let tabID: UUID
    let line: Int
    let range: NSRange
}

/// The matches on one line, with the exact text they were found in. A
/// page can be drawn with newer content than the last search saw (a load
/// lands before the re-search), so views check `text` before using
/// `ranges`.
struct LineHighlights {
    let text: String
    let ranges: [NSRange]
}

extension TabContent {
    /// The page's text as find sees it, one entry per rendered line.
    var findableLines: [String] {
        switch self {
        case .menu(let items):
            return items.map(\.display)
        case .text(let text):
            return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        case .home, .image, .error:
            return []
        }
    }
}

/// Find on Page (⌘F) for one window: the query and options, the matches
/// in the current tab (or all tabs), and which match is current.
@MainActor
final class PageFinder: ObservableObject {
    static let maxMatches = 10_000

    @Published private(set) var isVisible = false
    @Published var query = "" {
        didSet { if query != oldValue { search(resetPosition: true) } }
    }
    @Published var usesRegex = false {
        didSet { if usesRegex != oldValue { search(resetPosition: true) } }
    }
    @Published var matchesCase = false {
        didSet { if matchesCase != oldValue { search(resetPosition: true) } }
    }
    @Published var searchesAllTabs = false {
        didSet { if searchesAllTabs != oldValue { search(resetPosition: true) } }
    }

    @Published private(set) var matches: [FindMatch] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var isPatternInvalid = false
    @Published private(set) var hitMatchLimit = false
    /// Bumped whenever the current match should be scrolled into view.
    @Published private(set) var revealRequest = 0
    /// Bumped when the search field should take keyboard focus.
    @Published private(set) var focusRequest = 0

    /// Matches grouped for rendering: tab → line → highlights.
    private(set) var highlights: [UUID: [Int: LineHighlights]] = [:]

    private weak var store: BrowserStore?
    private var contentWatch: AnyCancellable?
    private var pendingReveal: FindMatch?

    init(store: BrowserStore) {
        self.store = store
    }

    var currentMatch: FindMatch? {
        currentIndex.map { matches[$0] }
    }

    var matchedTabCount: Int {
        Set(matches.map(\.tabID)).count
    }

    // MARK: - Showing and hiding

    func show() {
        if !isVisible {
            isVisible = true
            watchContent()
            search(resetPosition: true)
        }
        focusRequest += 1
    }

    func hide() {
        guard isVisible else { return }
        isVisible = false
        contentWatch = nil
        clearMatches()
    }

    // MARK: - Moving between matches

    func findNext() { step(by: 1) }
    func findPrevious() { step(by: -1) }

    private func step(by delta: Int) {
        if !isVisible { show() }
        guard !matches.isEmpty else { return }
        if let currentIndex {
            self.currentIndex = (currentIndex + delta + matches.count) % matches.count
        } else {
            // Nothing on this page; head for the nearest tab that has some.
            currentIndex = nearestMatchIndex(forward: delta > 0)
        }
        revealCurrent()
    }

    private func nearestMatchIndex(forward: Bool) -> Int? {
        guard let store, let selected = store.selectedTabID,
              let start = store.tabs.firstIndex(where: { $0.id == selected }) else {
            return forward ? 0 : matches.count - 1
        }
        let order = store.tabs.map(\.id)
        for offset in 1...order.count {
            let position = forward ? start + offset : start - offset + order.count
            let candidate = order[position % order.count]
            let index = forward ? matches.firstIndex(where: { $0.tabID == candidate })
                                : matches.lastIndex(where: { $0.tabID == candidate })
            if let index { return index }
        }
        return nil
    }

    private func revealCurrent() {
        pendingReveal = currentMatch
        if let match = currentMatch, let store, match.tabID != store.selectedTabID,
           let tab = store.tabs.first(where: { $0.id == match.tabID }) {
            store.selectTab(tab)
        }
        revealRequest += 1
    }

    // MARK: - Searching

    /// Re-runs the search. `resetPosition` starts from the first match in
    /// the selected tab (a new query); otherwise the current match is kept
    /// if it still exists (content changed underneath it).
    func search(resetPosition: Bool) {
        guard isVisible, let store, !query.isEmpty else {
            clearMatches()
            return
        }
        let options: NSRegularExpression.Options = matchesCase ? [] : [.caseInsensitive]
        let pattern = usesRegex ? query : NSRegularExpression.escapedPattern(for: query)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            clearMatches()
            isPatternInvalid = true
            return
        }

        let previous = currentMatch
        let tabs = searchesAllTabs ? store.tabs : store.tabs.filter { $0.id == store.selectedTabID }
        var found: [FindMatch] = []
        var grouped: [UUID: [Int: LineHighlights]] = [:]
        var limited = false

        search: for tab in tabs {
            for (lineIndex, line) in tab.content.findableLines.enumerated() {
                let whole = NSRange(line.startIndex..., in: line)
                var lineRanges: [NSRange] = []
                defer {
                    if !lineRanges.isEmpty {
                        grouped[tab.id, default: [:]][lineIndex] = LineHighlights(text: line, ranges: lineRanges)
                    }
                }
                for result in regex.matches(in: line, range: whole) where result.range.length > 0 {
                    if found.count == Self.maxMatches {
                        limited = true
                        break search
                    }
                    found.append(FindMatch(tabID: tab.id, line: lineIndex, range: result.range))
                    lineRanges.append(result.range)
                }
            }
        }

        isPatternInvalid = false
        hitMatchLimit = limited
        matches = found
        highlights = grouped

        if !resetPosition, let previous, let kept = found.firstIndex(of: previous) {
            currentIndex = kept
            return
        }
        // Search-as-you-type stays on the current page; Next/Previous are
        // what move on to other tabs. A page that merely reloaded or
        // changed keeps its scroll position.
        currentIndex = found.firstIndex { $0.tabID == store.selectedTabID }
        if resetPosition, currentIndex != nil { revealCurrent() }
    }

    /// Hands the pending scroll-to-match to the page view showing `tabID`,
    /// once; a view appearing later for another reason won't jump.
    func takeReveal(for tabID: UUID) -> FindMatch? {
        guard let match = pendingReveal, match.tabID == tabID, match == currentMatch else { return nil }
        pendingReveal = nil
        return match
    }

    private func clearMatches() {
        matches = []
        highlights = [:]
        currentIndex = nil
        isPatternInvalid = false
        hitMatchLimit = false
    }

    /// Re-searches when tabs open, close, switch, or load new pages.
    private func watchContent() {
        guard let store else { return }
        let pageChanges = store.$tabs
            .map { tabs in Publishers.MergeMany(tabs.map { $0.$content.map { _ in () } }) }
            .switchToLatest()
        contentWatch = Publishers.Merge3(
            pageChanges,
            store.$tabs.map { _ in () },
            store.$selectedTabID.map { _ in () }
        )
        // @Published fires before the new value is stored; the delay
        // also coalesces bursts (e.g. a tab switch plus its page load).
        .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
        .sink { [weak self] in
            MainActor.assumeIsolated { self?.search(resetPosition: false) }
        }
    }
}
