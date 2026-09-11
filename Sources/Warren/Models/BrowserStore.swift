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

@MainActor
final class BrowserStore: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var selectedTabID: UUID?
    @Published var addressBarText = ""
    @Published var searchPrompt: SearchPrompt?
    @Published var statusMessage = ""
    @Published var showHistoryManager = false

    /// Global visit history; injected so both stores stay app-owned.
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
        tabs.remove(at: index)
        if tabs.isEmpty {
            newTab()
        } else if selectedTabID == tab.id {
            selectTab(tabs[min(index, tabs.count - 1)])
        }
    }

    func closeSelectedTab() {
        if let tab = selectedTab { closeTab(tab) }
    }

    func selectTab(_ tab: BrowserTab) {
        selectedTabID = tab.id
        addressBarText = tab.currentAddress?.displayString ?? ""
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

    /// Entry point for clicking a menu item.
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
        if inNewTab || tabs.isEmpty {
            tab = newTab()
        } else {
            tab = selectedTab ?? newTab()
        }

        // Push onto history, discarding any forward entries.
        if tab.historyIndex < tab.history.count - 1 {
            tab.history.removeSubrange((tab.historyIndex + 1)...)
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

    func goBack() {
        guard let tab = selectedTab, tab.canGoBack else { return }
        tab.historyIndex -= 1
        showHistoryEntry(tab)
    }

    func goForward() {
        guard let tab = selectedTab, tab.canGoForward else { return }
        tab.historyIndex += 1
        showHistoryEntry(tab)
    }

    func reload() {
        guard let tab = selectedTab, let address = tab.currentAddress else { return }
        load(tab: tab, address: address, cacheInto: tab.historyIndex)
    }

    func goHome() {
        guard let tab = selectedTab else { return }
        tab.loadGeneration += 1
        tab.isLoading = false
        tab.content = .home
        tab.title = "New Tab"
        addressBarText = ""
    }

    private func showHistoryEntry(_ tab: BrowserTab) {
        let entry = tab.history[tab.historyIndex]
        addressBarText = entry.address.displayString
        tab.title = entry.title
        if let cached = entry.content {
            tab.loadGeneration += 1 // invalidate any in-flight load
            tab.isLoading = false
            tab.content = cached
        } else {
            load(tab: tab, address: entry.address, cacheInto: tab.historyIndex)
        }
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
