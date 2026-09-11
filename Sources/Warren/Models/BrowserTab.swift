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

@MainActor
final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    @Published var history: [HistoryEntry] = []
    @Published var historyIndex: Int = -1
    @Published var content: TabContent = .home
    @Published var isLoading = false
    @Published var title = "New Tab"

    /// Serial number of the most recent load; stale loads are dropped.
    var loadGeneration = 0

    var currentAddress: GopherAddress? {
        guard history.indices.contains(historyIndex) else { return nil }
        return history[historyIndex].address
    }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }
}
