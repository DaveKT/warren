import SwiftUI

@main
struct WarrenApp: App {
    @StateObject private var store = BrowserStore()
    @StateObject private var bookmarks = BookmarkStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(bookmarks)
                .frame(minWidth: 700, minHeight: 450)
        }
        .defaultSize(width: 1000, height: 720)
        .commands {
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
            CommandMenu("Bookmarks") {
                Button("Add Bookmark…") { addCurrentBookmark() }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(store.selectedTab?.currentAddress == nil)
                Divider()
                ForEach(bookmarks.bookmarks) { bookmark in
                    Button(bookmark.title) {
                        if let address = bookmark.address { store.open(address, title: bookmark.title) }
                    }
                }
            }
        }
    }

    private var canExportCurrent: Bool {
        guard let tab = store.selectedTab else { return false }
        return PageExporter.canExport(tab.content)
    }

    private func addCurrentBookmark() {
        guard let tab = store.selectedTab, let address = tab.currentAddress else { return }
        bookmarks.add(title: tab.title, address: address)
    }
}
