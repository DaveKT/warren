import SwiftUI

@main
struct WarrenApp: App {
    @StateObject private var store: BrowserStore
    @StateObject private var bookmarks = BookmarkStore()
    @StateObject private var history: HistoryStore

    init() {
        let history = HistoryStore()
        _history = StateObject(wrappedValue: history)
        _store = StateObject(wrappedValue: BrowserStore(history: history))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(bookmarks)
                .environmentObject(history)
                .frame(minWidth: 700, minHeight: 450)
                // gopher:// links from other apps: any existing window may
                // claim the event (so no new window is spawned)…
                .handlesExternalEvents(preferring: [], allowing: ["*"])
                // …and the link opens in a new tab of that window.
                .onOpenURL { store.openExternal($0) }
        }
        .defaultSize(width: 1000, height: 720)
        .commands {
            CommandGroup(replacing: .help) {
                OpenHelpButton()
            }
            CommandGroup(after: .newItem) {
                Button("New Tab") { store.newTab() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("Close Tab") { store.closeSelectedTab() }
                    .keyboardShortcut("w", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save as Text…") {
                    if let tab = store.selectedTab { PageExporter.export(tab: tab, format: .plainText) }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!canExportCurrent)

                Button("Save as Markdown…") {
                    if let tab = store.selectedTab { PageExporter.export(tab: tab, format: .markdown) }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!canExportCurrent)
            }
            CommandGroup(after: .toolbar) {
                Divider()
                TextSizeCommands()
            }
            CommandMenu("Go") {
                Button("Back") { store.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!(store.selectedTab?.canGoBack ?? false))
                Button("Forward") { store.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!(store.selectedTab?.canGoForward ?? false))
                Button("Reload Page") { store.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(store.selectedTab?.currentAddress == nil)
                Divider()
                Button("Home") { store.goHome() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Divider()
                Button("Show Next Tab") { store.selectNextTab() }
                    .keyboardShortcut(.tab, modifiers: .control)
                    .disabled(store.tabs.count < 2)
                Button("Show Previous Tab") { store.selectPreviousTab() }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])
                    .disabled(store.tabs.count < 2)
            }
            CommandMenu("History") {
                Button("Show All History…") { store.showHistoryManager = true }
                    .keyboardShortcut("y", modifiers: .command)
                Divider()
                ForEach(history.items.prefix(15)) { item in
                    Button(item.title) {
                        if let address = item.address { store.open(address, title: item.title) }
                    }
                }
                if !history.items.isEmpty { Divider() }
                Menu("Clear History") {
                    ForEach(HistoryStore.ClearRange.allCases, id: \.self) { range in
                        Button(range.label) { history.confirmAndClear(range) }
                    }
                }
                .disabled(history.items.isEmpty)
            }
            CommandMenu("Bookmarks") {
                Button("Add Bookmark…") { store.showAddBookmark = true }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(store.selectedTab?.currentAddress == nil)
                Divider()
                BookmarkMenuItems(nodes: bookmarks.root)
                    .environmentObject(store)
            }
        }

        Window("Warren Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 660, height: 580)
    }

    private var canExportCurrent: Bool {
        guard let tab = store.selectedTab else { return false }
        return PageExporter.canExport(tab.content)
    }
}

/// View menu commands for the content text size (⌘+ / ⌘− / ⌘0).
/// Only page content scales; window chrome stays at the default size.
private struct TextSizeCommands: View {
    @AppStorage(ContentTextSize.storageKey) private var size = ContentTextSize.default

    var body: some View {
        Button("Make Text Bigger") { size = min(size + ContentTextSize.step, ContentTextSize.range.upperBound) }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(size >= ContentTextSize.range.upperBound)
        Button("Make Text Smaller") { size = max(size - ContentTextSize.step, ContentTextSize.range.lowerBound) }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(size <= ContentTextSize.range.lowerBound)
        Button("Actual Size") { size = ContentTextSize.default }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(size == ContentTextSize.default)
    }
}

/// Menu items can't read @Environment(\.openWindow) directly from the
/// App struct, so the Help command lives in its own little view.
private struct OpenHelpButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Warren Help") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}
