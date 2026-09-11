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

/// Menu items can't read @Environment(\.openWindow) directly from the
/// App struct, so the Help command lives in its own little view.
private struct OpenHelpButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Warren Help") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}
