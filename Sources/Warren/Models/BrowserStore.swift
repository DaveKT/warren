import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A pending prompt for a type 7 (index-search) or type 2 (CSO) item.
struct SearchPrompt: Identifiable {
    let id = UUID()
    var address: GopherAddress
    var itemTitle: String
}

/// A tab closed in this session, kept so it can be reopened with its
/// history and cached pages intact. Also serves as the undo target, so
/// its undo action can be dropped when it ages out of the list.
private final class ClosedTab {
    let tab: BrowserTab
    let index: Int

    init(tab: BrowserTab, index: Int) {
        self.tab = tab
        self.index = index
    }
}

/// The tabs and navigation state of one browser window.
@MainActor
final class BrowserStore: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var selectedTabID: UUID?
    @Published var addressBarText = ""
    @Published var searchPrompt: SearchPrompt?
    @Published var statusMessage = ""
    /// The menu link under the pointer ("Menu · gopher://…"), shown in a
    /// small overlay at the bottom of the page.
    @Published var linkHoverStatus: String?
    @Published var showHistoryManager = false
    @Published var showAddBookmark = false

    static let maxClosedTabs = 20
    @Published private var closedTabs: [ClosedTab] = []

    /// Find on Page (⌘F) for this window.
    private(set) lazy var finder = PageFinder(store: self)

    /// Two-finger swipe Back/Forward for this window.
    private(set) lazy var swipe = SwipeNavigator(store: self)

    /// The window's undo manager, shared with its text fields so ⌘Z
    /// undoes typing while editing and reopens closed tabs otherwise.
    weak var undoManager: UndoManager? {
        didSet {
            guard undoManager !== oldValue else { return }
            observeUndoGroups()
        }
    }

    /// Undo targets (closed-tab entries and their tabs) whose actions must
    /// be dropped once the current undo group closes; removing them while
    /// a group is open leaves dead steps on the undo stack. Held strongly
    /// until then, since UndoManager doesn't retain targets.
    private var pendingUndoRemovals: [AnyObject] = []
    private var undoGroupObserver: NSObjectProtocol?

    deinit {
        if let undoGroupObserver { NotificationCenter.default.removeObserver(undoGroupObserver) }
    }

    /// Global visit history; injected so it stays app-owned and shared
    /// across windows.
    let historyStore: HistoryStore?

    init(history: HistoryStore? = nil) {
        historyStore = history
        newTab()
    }

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedTabID }
    }

    // MARK: - Tabs

    @discardableResult
    func newTab(select: Bool = true) -> BrowserTab {
        let tab = BrowserTab()
        tabs.append(tab)
        if select { selectTab(tab) }
        return tab
    }

    func closeTab(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        // Undo Close Tab brings the tab back showing its page, not the image.
        closeImage(in: tab)
        tabs.remove(at: index)
        if tabs.isEmpty {
            newTab()
        } else if selectedTabID == tab.id {
            selectTab(tabs[min(index, tabs.count - 1)])
        }
        // A blank tab has nothing worth bringing back.
        if !tab.history.isEmpty {
            rememberClosedTab(ClosedTab(tab: tab, index: index))
        }
    }

    /// Close Tab (⌘W) closes an open image before the tab itself.
    func closeSelectedTab() {
        guard let tab = selectedTab else { return }
        if tab.lightbox != nil {
            closeImage(in: tab)
        } else {
            closeTab(tab)
        }
    }

    var canReopenClosedTab: Bool { !closedTabs.isEmpty }

    /// Reopen Closed Tab (⇧⌘T): brings back the most recently closed tab
    /// without going through the undo stack.
    func reopenLastClosedTab() {
        guard let entry = closedTabs.last else { return }
        removeUndoActions(for: entry)
        reopen(entry)
        undoManager?.setActionName("Reopen Closed Tab")
    }

    private func rememberClosedTab(_ entry: ClosedTab) {
        closedTabs.append(entry)
        if closedTabs.count > Self.maxClosedTabs {
            // The tab is about to be deallocated; any "close it again"
            // action from an earlier reopen must go with it.
            let old = closedTabs.removeFirst()
            removeUndoActions(for: old, old.tab)
        }
        undoManager?.registerUndo(withTarget: entry) { [weak self] entry in
            MainActor.assumeIsolated { self?.reopen(entry) }
        }
        undoManager?.setActionName("Close Tab")
    }

    private func reopen(_ entry: ClosedTab) {
        guard let position = closedTabs.firstIndex(where: { $0 === entry }) else { return }
        closedTabs.remove(at: position)

        // Closing the last tab leaves a blank one behind; take its place.
        if tabs.count == 1, tabs[0].history.isEmpty {
            tabs = [entry.tab]
        } else {
            tabs.insert(entry.tab, at: min(entry.index, tabs.count))
        }
        selectTab(entry.tab)

        // Registering the inverse while undoing makes it the redo action.
        undoManager?.registerUndo(withTarget: entry.tab) { [weak self] tab in
            MainActor.assumeIsolated { self?.closeTab(tab) }
        }
        undoManager?.setActionName("Close Tab")
    }

    private func removeUndoActions(for targets: AnyObject...) {
        guard let undoManager else { return }
        if undoManager.groupingLevel == 0 {
            for target in targets { undoManager.removeAllActions(withTarget: target) }
        } else {
            pendingUndoRemovals.append(contentsOf: targets)
        }
    }

    private func observeUndoGroups() {
        if let undoGroupObserver { NotificationCenter.default.removeObserver(undoGroupObserver) }
        undoGroupObserver = nil
        pendingUndoRemovals.removeAll()
        guard let undoManager else { return }
        undoGroupObserver = NotificationCenter.default.addObserver(
            forName: .NSUndoManagerDidCloseUndoGroup, object: undoManager, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushPendingUndoRemovals() }
        }
    }

    private func flushPendingUndoRemovals() {
        guard let undoManager, undoManager.groupingLevel == 0, !pendingUndoRemovals.isEmpty else { return }
        let entries = pendingUndoRemovals
        pendingUndoRemovals.removeAll()
        for target in entries { undoManager.removeAllActions(withTarget: target) }
    }

    func selectTab(_ tab: BrowserTab) {
        selectedTabID = tab.id
        addressBarText = tab.currentAddress?.displayString ?? ""
        if tab.needsRestoredPage {
            tab.needsRestoredPage = false
            showHistoryEntry(tab)
        }
    }

    func selectNextTab() {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        selectTab(tabs[(index + 1) % tabs.count])
    }

    func selectPreviousTab() {
        guard tabs.count > 1,
              let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        selectTab(tabs[(index + tabs.count - 1) % tabs.count])
    }

    /// Drag-and-drop reordering: moves the dragged tab into the slot of
    /// the tab it is currently hovering over.
    func moveTab(id draggedID: UUID, over targetID: UUID) {
        guard draggedID != targetID,
              let from = tabs.firstIndex(where: { $0.id == draggedID }),
              let to = tabs.firstIndex(where: { $0.id == targetID }) else { return }
        tabs.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    // MARK: - Session

    /// This store's window, for saving its frame and stacking order.
    weak var window: NSWindow? {
        didSet { applyPendingFrame() }
    }

    /// A restored window's saved frame, applied once the window exists.
    private var pendingFrame: CGRect?

    /// No tab in this window has been anywhere yet.
    var isPristine: Bool { tabs.allSatisfy { $0.history.isEmpty } }

    /// This window as saved in a session; nil when all its tabs are blank,
    /// which are left out like they are for Undo Close Tab.
    func sessionSnapshot() -> SessionSnapshot.Window? {
        var saved: [SessionSnapshot.Tab] = []
        var selected = 0
        for tab in tabs {
            let snapshot = tab.sessionSnapshot
            if tab.id == selectedTabID {
                // A blank selected tab hands selection to the tab before it.
                selected = snapshot == nil ? max(saved.count - 1, 0) : saved.count
            }
            if let snapshot { saved.append(snapshot) }
        }
        guard !saved.isEmpty else { return nil }
        return SessionSnapshot.Window(frame: window?.frame, tabs: saved, selectedTab: selected)
    }

    /// Replaces this window's tabs with a saved window's. Only the
    /// selected tab loads now; the others load when first shown.
    func restore(_ snapshot: SessionSnapshot.Window) {
        let restored = snapshot.tabs.compactMap(BrowserTab.init(restoring:))
        guard !restored.isEmpty else { return }
        tabs = restored
        selectTab(restored[min(max(snapshot.selectedTab, 0), restored.count - 1)])
        pendingFrame = snapshot.frame
        applyPendingFrame()
    }

    private func applyPendingFrame() {
        guard let window, let frame = pendingFrame else { return }
        pendingFrame = nil
        // Skip a frame from a display that's no longer connected.
        guard NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else { return }
        window.setFrame(frame, display: true)
    }

    // MARK: - Navigation

    /// Entry point for the address bar.
    func submitAddressBar() {
        guard let address = GopherAddress.parse(addressBarText) else {
            statusMessage = "Not a valid Gopher address."
            return
        }
        open(address)
    }

    /// Entry point for gopher:// URLs handed to us by macOS — links
    /// clicked in Safari, PDFs, or other apps. Opens in a new tab, unless
    /// the current tab is still blank (e.g. a window macOS just created
    /// to receive the link).
    func openExternal(_ url: URL) {
        guard let address = GopherAddress.parse(url.absoluteString) else {
            statusMessage = "Not a valid Gopher address: \(url.absoluteString)"
            return
        }
        let reuseBlankTab = selectedTab?.history.isEmpty ?? false
        open(address, inNewTab: !reuseBlankTab)
    }

    /// Entry point for clicking a menu item. An image opens in a lightbox
    /// over the page unless it's going to a new tab.
    func open(item: GopherItem, inNewTab: Bool = false) {
        guard let address = item.address else { return }
        switch item.type {
        case .telnet, .tn3270:
            openTelnet(address)
        case .html:
            if openExternalURL(from: address) { return }
            open(address, title: item.display, inNewTab: inNewTab)
        case .search, .csoServer:
            searchPrompt = SearchPrompt(address: address, itemTitle: item.display)
        case .some(let t) where t.isBinaryDownload:
            download(address, suggestedName: item.display)
        case .none:
            download(address, suggestedName: item.display) // unknown type: save raw
        case .some(let t) where t.isImage && !inNewTab && selectedTab != nil:
            showImage(address, title: item.display)
        default:
            open(address, title: item.display, inNewTab: inNewTab)
        }
    }

    /// Navigates the current (or a new) tab to an address, pushing history.
    func open(_ address: GopherAddress, title: String? = nil, inNewTab: Bool = false) {
        // Addresses typed or followed directly can still be special types.
        if let type = address.type {
            if type == .search, address.searchQuery == nil {
                searchPrompt = SearchPrompt(address: address, itemTitle: title ?? "Search")
                return
            }
            if type.isBinaryDownload {
                download(address, suggestedName: title ?? lastPathComponent(of: address))
                return
            }
            if type == .telnet || type == .tn3270 {
                openTelnet(address)
                return
            }
            if type == .html, openExternalURL(from: address) { return }
        }

        let tab: BrowserTab
        if !inNewTab, let selected = selectedTab {
            tab = selected
            // Leaving the Home page of a blank tab: Back returns to it.
            if tab.history.isEmpty { tab.startedAtHome = true }
        } else {
            tab = newTab()
        }
        swipe.capturePage(of: tab)
        closeImage(in: tab)

        // Push onto history, discarding any forward entries (and their
        // remembered scroll offsets and pictures, since those indexes get
        // reused).
        if tab.historyIndex < tab.history.count - 1 {
            tab.history.removeSubrange((tab.historyIndex + 1)...)
            tab.scrollOffsets = tab.scrollOffsets.filter { $0.key < tab.history.count }
            tab.snapshots = tab.snapshots.filter { $0.key < tab.history.count }
        }
        tab.history.append(HistoryEntry(address: address, title: title ?? address.displayString))
        tab.historyIndex = tab.history.count - 1

        historyStore?.record(address: address, title: title ?? address.displayString)
        load(tab: tab, address: address, cacheInto: tab.historyIndex)
    }

    func submitSearch(query: String) {
        guard let prompt = searchPrompt else { return }
        searchPrompt = nil
        var address = prompt.address
        address.searchQuery = query
        open(address, title: "\(prompt.itemTitle): \(query)")
    }

    /// Back closes an open image instead of leaving the page.
    func goBack() {
        guard let tab = selectedTab else { return }
        if tab.lightbox != nil {
            closeImage(in: tab)
            return
        }
        guard tab.canGoBack else { return }
        swipe.capturePage(of: tab)
        tab.historyIndex -= 1
        showHistoryEntry(tab)
    }

    func goForward() {
        guard let tab = selectedTab, tab.canGoForward else { return }
        swipe.capturePage(of: tab)
        closeImage(in: tab)
        tab.historyIndex += 1
        showHistoryEntry(tab)
    }

    /// Reloads the open image if there is one, otherwise the page.
    func reload() {
        guard let tab = selectedTab else { return }
        if tab.lightbox != nil {
            fetchImage(into: tab)
            return
        }
        guard let address = tab.currentAddress else { return }
        load(tab: tab, address: address, cacheInto: tab.historyIndex)
    }

    func goHome() {
        guard let tab = selectedTab else { return }
        swipe.capturePage(of: tab)
        closeImage(in: tab)
        tab.loadGeneration += 1
        tab.isLoading = false
        tab.content = .home
        tab.title = "New Tab"
        addressBarText = ""
    }

    private func showHistoryEntry(_ tab: BrowserTab) {
        // Back from the first page of a tab that started on Home.
        guard tab.history.indices.contains(tab.historyIndex) else {
            tab.loadGeneration += 1 // invalidate any in-flight load
            tab.isLoading = false
            tab.content = .home
            tab.title = "New Tab"
            addressBarText = ""
            statusMessage = ""
            return
        }
        let entry = tab.history[tab.historyIndex]
        addressBarText = entry.address.displayString
        tab.title = entry.title
        tab.pendingScrollRestore = tab.scrollOffsets[tab.historyIndex]
        if let cached = entry.content {
            tab.loadGeneration += 1 // invalidate any in-flight load
            tab.isLoading = false
            tab.content = cached
        } else {
            load(tab: tab, address: entry.address, cacheInto: tab.historyIndex)
        }
    }

    // MARK: - Lightbox

    /// Shows an image linked from the current page in a lightbox over it,
    /// without navigating: the visit goes into History but not into the
    /// tab's back/forward list.
    func showImage(_ address: GopherAddress, title: String) {
        guard let tab = selectedTab else { return }
        historyStore?.record(address: address, title: title)
        setLightbox(Lightbox(address: address, title: title), in: tab)
        fetchImage(into: tab)
    }

    /// Fetches the tab's lightbox image: when it opens, and again for
    /// Reload or Try Again.
    func fetchImage(into tab: BrowserTab) {
        guard let address = tab.lightbox?.address else { return }
        tab.lightboxFetch?.cancel()
        tab.lightboxGeneration += 1
        let generation = tab.lightboxGeneration
        tab.lightbox?.state = .loading
        statusMessage = "Connecting to \(address.host)…"

        tab.lightboxFetch = Task {
            let state: Lightbox.State
            do {
                let data = try await GopherClient.fetch(address)
                if let image = NSImage(data: data) {
                    state = .loaded(image)
                } else {
                    state = .failed("The server sent something that isn't an image Warren can show.")
                }
            } catch is CancellationError {
                return
            } catch {
                state = .failed(error.localizedDescription)
            }

            guard tab.lightboxGeneration == generation else { return } // closed or superseded
            tab.lightbox?.state = state
            tab.lightboxFetch = nil
            if case .loaded = state {
                // As for a page: History lists it by name, not by link text.
                historyStore?.updateTitle(for: address, title: Self.title(for: address))
            }
            statusMessage = ""
        }
    }

    /// Closes the tab's image, if it has one, uncovering the page.
    func closeImage(in tab: BrowserTab) {
        guard let lightbox = tab.lightbox else { return }
        tab.lightboxGeneration += 1 // drop any fetch still in flight
        tab.lightboxFetch?.cancel()
        tab.lightboxFetch = nil
        if case .loading = lightbox.state { statusMessage = "" }
        setLightbox(nil, in: tab)
    }

    /// Back, Reload, and Close Tab change what they do while an image is
    /// open; the menus and toolbar watch this store, not the tab.
    ///
    /// The image fades in and out here rather than with an implicit
    /// animation in the view, which would also fade one tab's image over
    /// another tab's page when switching tabs.
    private func setLightbox(_ lightbox: Lightbox?, in tab: BrowserTab) {
        objectWillChange.send()
        if lightbox != nil { linkHoverStatus = nil } // the link under the pointer is covered
        withAnimation(.easeOut(duration: 0.15)) { tab.lightbox = lightbox }
    }

    // MARK: - Loading

    private func load(tab: BrowserTab, address: GopherAddress, cacheInto historyIndex: Int) {
        tab.loadGeneration += 1
        let generation = tab.loadGeneration
        tab.isLoading = true
        if selectedTabID == tab.id {
            addressBarText = address.displayString
        }
        statusMessage = "Connecting to \(address.host)…"

        Task {
            let content: TabContent
            var pageTitle: String? = nil
            do {
                let data = try await GopherClient.fetch(address)
                switch address.type {
                case .menu, .search, .redundant, .none:
                    content = .menu(GopherMenuParser.parse(data))
                case .some(let t) where t.isImage:
                    content = .image(data)
                case .csoServer:
                    content = .text(GopherText.decode(data))
                default:
                    content = .text(GopherText.decodeTextFile(data))
                }
                pageTitle = Self.title(for: address)
            } catch is CancellationError {
                return
            } catch {
                content = .error(error.localizedDescription)
            }

            guard tab.loadGeneration == generation else { return } // superseded
            tab.isLoading = false
            tab.content = content
            if let pageTitle { tab.title = pageTitle }
            if tab.history.indices.contains(historyIndex) {
                tab.history[historyIndex].content = content
                if let pageTitle { tab.history[historyIndex].title = pageTitle }
            }
            if let pageTitle {
                historyStore?.updateTitle(for: address, title: pageTitle)
            }
            statusMessage = ""
        }
    }

    private static func title(for address: GopherAddress) -> String {
        if let query = address.searchQuery { return "Search: \(query)" }
        let component = address.selector
            .split(separator: "/", omittingEmptySubsequences: true).last.map(String.init)
        if let component, !component.isEmpty { return component }
        return address.host
    }

    private func lastPathComponent(of address: GopherAddress) -> String {
        address.selector.split(separator: "/", omittingEmptySubsequences: true)
            .last.map(String.init) ?? "download"
    }

    // MARK: - Special item types

    private func openTelnet(_ address: GopherAddress) {
        // RFC 1436 type 8/T: the selector, if present, is the login account.
        var s = "telnet://"
        if !address.selector.isEmpty { s += "\(address.selector)@" }
        s += "\(address.host):\(address.port)"
        if let url = URL(string: s) {
            NSWorkspace.shared.open(url)
        }
    }

    /// For type h items whose selector is "URL:http://...": open externally.
    private func openExternalURL(from address: GopherAddress) -> Bool {
        guard address.selector.uppercased().hasPrefix("URL:") else { return false }
        let raw = String(address.selector.dropFirst(4))
        guard let url = URL(string: raw), url.scheme != nil else { return false }
        NSWorkspace.shared.open(url)
        return true
    }

    // MARK: - Downloads

    func download(_ address: GopherAddress, suggestedName: String) {
        let panel = NSSavePanel()
        panel.title = "Download from \(address.host)"
        panel.nameFieldStringValue = sanitizeFilename(suggestedName)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        statusMessage = "Downloading \(suggestedName)…"
        Task {
            do {
                let data = try await GopherClient.fetch(address)
                try data.write(to: url)
                statusMessage = "Saved \(url.lastPathComponent)."
            } catch {
                statusMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    private func sanitizeFilename(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "download" : cleaned
    }
}
