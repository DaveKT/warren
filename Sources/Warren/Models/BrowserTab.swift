import AppKit
import Foundation

/// What a tab is currently showing.
enum TabContent {
    case home
    case menu([GopherItem])
    case text(String)
    case image(Data)
    case error(String)
}

struct HistoryEntry {
    var address: GopherAddress
    var title: String
    /// Cached content so Back/Forward are instant; Reload refetches.
    var content: TabContent?
}

/// An image opened from a link on the page, shown in a lightbox over the
/// tab's page. It belongs to the tab but not to its back/forward history.
struct Lightbox: Identifiable {
    enum State {
        case loading
        case loaded(NSImage)
        case failed(String)
    }

    let id = UUID()
    var address: GopherAddress
    var title: String
    var state: State = .loading
}

@MainActor
final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    @Published var history: [HistoryEntry] = []
    @Published var historyIndex: Int = -1
    @Published var content: TabContent = .home
    @Published var isLoading = false
    @Published var title = "New Tab"

    /// The image showing over the page, if any. Each tab keeps its own, so
    /// switching tabs hides it and switching back shows it again.
    @Published var lightbox: Lightbox?

    /// Serial number of the most recent load; stale loads are dropped.
    var loadGeneration = 0

    /// Serial number of the most recent lightbox fetch, likewise.
    var lightboxGeneration = 0

    /// The lightbox image download, cancelled if the image is closed first.
    var lightboxFetch: Task<Void, Never>?

    /// Last known scroll offset per history index, kept outside @Published
    /// state so scrolling doesn't trigger view updates. Used to restore
    /// position on Back/Forward; transient, in-memory only.
    var scrollOffsets: [Int: CGPoint] = [:]

    /// Pictures of pages as they looked when the user left them, per
    /// history index, for the swipe slide. In memory only.
    var snapshots: [Int: PageSnapshot] = [:]

    /// Offset the next page view should jump to once laid out (set by
    /// Back/Forward navigation, consumed by ScrollMemory).
    var pendingScrollRestore: CGPoint?

    /// Reopened from the last session without its page; the page is
    /// fetched when the tab is first shown.
    var needsRestoredPage = false

    /// The tab showed Home before its first page, so Back from that page
    /// returns to Home (history index -1). False for tabs opened straight
    /// to a page, such as a link opened in a new tab.
    var startedAtHome = false

    /// Showing Home rather than a page.
    var isShowingHome: Bool {
        if case .home = content { return true }
        return false
    }

    var currentAddress: GopherAddress? {
        guard history.indices.contains(historyIndex) else { return nil }
        return history[historyIndex].address
    }

    /// Back also closes an open image, even on the tab's first page. From
    /// the first page it goes to Home if the tab started there (but not
    /// when Go → Home is already showing Home over that page).
    var canGoBack: Bool {
        historyIndex > 0 || lightbox != nil
            || (historyIndex == 0 && startedAtHome && !isShowingHome)
    }

    /// From Home (index -1) Forward goes to the first page.
    var canGoForward: Bool { historyIndex < history.count - 1 }
}
