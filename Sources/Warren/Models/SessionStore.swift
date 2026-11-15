import AppKit
import Foundation

/// The browser windows and tabs open when Warren last quit. Only addresses
/// and titles are kept; pages are fetched again when a restored tab is
/// first shown.
struct SessionSnapshot: Codable {
    struct Window: Codable {
        var frame: CGRect?
        var tabs: [Tab]
        var selectedTab: Int
    }

    struct Tab: Codable {
        var entries: [Entry]
        var historyIndex: Int
        /// The tab was showing Home (Go → Home) over its history.
        var showsHome: Bool
        /// Back from the first page returns to Home; historyIndex is -1
        /// when the tab had gone back there. Missing in older sessions.
        var startedAtHome: Bool?
    }

    struct Entry: Codable {
        var url: String
        var title: String
    }

    /// Back to front, so reopening them in order leaves the frontmost
    /// window in front.
    var windows: [Window]
}

/// Restore Last Session: saves the open windows to session.json at quit,
/// and reopens them from History → Reopen All Windows from Last Session,
/// or at launch when that's turned on in Settings.
@MainActor
final class SessionStore: ObservableObject {
    static let restoreAtLaunchKey = "restoreSessionAtLaunch"

    /// The session saved at the last quit, until it's reopened.
    @Published private(set) var lastSession: SessionSnapshot?

    var canRestore: Bool { lastSession != nil }

    private struct WeakStore {
        weak var store: BrowserStore?
    }

    private var windows: [WeakStore] = []
    /// Saved windows waiting for a newly opened window to claim them.
    private var pendingWindows: [SessionSnapshot.Window] = []
    private var didLaunch = false
    private let fileURL: URL
    private var terminateObserver: NSObjectProtocol?

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Warren", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("session.json")
        load()
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    deinit {
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
    }

    /// Called as each browser window appears. A window opened to reopen
    /// the session takes the next saved window; the first window at launch
    /// reopens the whole session when the setting is on.
    func register(_ store: BrowserStore, openNewWindow: @escaping () -> Void) {
        windows.removeAll { $0.store == nil }
        guard !windows.contains(where: { $0.store === store }) else { return }
        windows.append(WeakStore(store: store))

        if !pendingWindows.isEmpty {
            store.restore(pendingWindows.removeFirst())
            return
        }
        guard !didLaunch else { return }
        didLaunch = true
        guard UserDefaults.standard.bool(forKey: Self.restoreAtLaunchKey) else { return }
        // Wait a turn so any windows macOS reopens itself, and a gopher://
        // link that launched the app, are in place first.
        DispatchQueue.main.async { [weak self] in
            self?.restore(openNewWindow: openNewWindow)
        }
    }

    /// Reopens the last session. Windows that are still blank (a fresh
    /// launch's first window) are filled first; the rest open new windows.
    func restore(openNewWindow: () -> Void) {
        guard let session = lastSession else { return }
        lastSession = nil
        var remaining = session.windows
        for store in liveStores where store.isPristine {
            guard !remaining.isEmpty else { break }
            store.restore(remaining.removeFirst())
        }
        pendingWindows = remaining
        for _ in remaining { openNewWindow() }
    }

    private var liveStores: [BrowserStore] {
        windows.compactMap(\.store)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let session = try? JSONDecoder().decode(SessionSnapshot.self, from: data),
              !session.windows.isEmpty else { return }
        lastSession = session
    }

    private func save() {
        // Front to back; minimized windows aren't listed and go to the back.
        let ordered = NSApp.orderedWindows
        let saved = liveStores.compactMap { store -> (depth: Int, window: SessionSnapshot.Window)? in
            guard let window = store.window, window.isVisible || window.isMiniaturized,
                  let snapshot = store.sessionSnapshot() else { return nil }
            return (ordered.firstIndex(of: window) ?? Int.max, snapshot)
        }
        let session = SessionSnapshot(windows: saved.sorted { $0.depth > $1.depth }.map(\.window))

        if session.windows.isEmpty {
            // Quitting with nothing open keeps a session that was never
            // reopened, so a quick launch-and-quit doesn't lose it.
            if lastSession == nil { try? FileManager.default.removeItem(at: fileURL) }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(session) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

extension BrowserTab {
    /// A tab rebuilt from the last session, without its pages.
    convenience init?(restoring snapshot: SessionSnapshot.Tab) {
        let entries = snapshot.entries.compactMap { entry in
            GopherAddress.parse(entry.url).map { HistoryEntry(address: $0, title: entry.title) }
        }
        guard !entries.isEmpty else { return nil }
        self.init()
        history = entries
        startedAtHome = snapshot.startedAtHome ?? false
        let lowest = startedAtHome ? -1 : 0
        historyIndex = min(max(snapshot.historyIndex, lowest), entries.count - 1)
        if historyIndex == -1 || snapshot.showsHome {
            title = "New Tab"
        } else {
            title = entries[historyIndex].title
            needsRestoredPage = true
        }
    }

    /// The tab as saved in a session; nil for a blank tab.
    var sessionSnapshot: SessionSnapshot.Tab? {
        // A blank tab has no history; one that went Back to Home does.
        guard !history.isEmpty,
              history.indices.contains(historyIndex) || (historyIndex == -1 && startedAtHome)
        else { return nil }
        let showsHome: Bool
        // A first page still loading also shows .home underneath.
        if case .home = content { showsHome = !isLoading && !needsRestoredPage } else { showsHome = false }
        return SessionSnapshot.Tab(
            entries: history.map { SessionSnapshot.Entry(url: $0.address.urlString, title: $0.title) },
            historyIndex: historyIndex,
            showsHome: showsHome && historyIndex >= 0,
            startedAtHome: startedAtHome)
    }
}
