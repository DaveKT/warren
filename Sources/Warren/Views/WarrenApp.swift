import SwiftUI

@main
struct WarrenApp: App {
    @StateObject private var bookmarks = BookmarkStore()
    @StateObject private var history = HistoryStore()
    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup(id: BrowserWindow.sceneID) {
            BrowserWindow(history: history, session: session)
                .environmentObject(bookmarks)
                .environmentObject(history)
                .frame(minWidth: 700, minHeight: 450)
                // gopher:// links from other apps: any existing window may
                // claim the event (so no new window is spawned).
                .handlesExternalEvents(preferring: [], allowing: ["*"])
        }
        .defaultSize(width: 1000, height: 720)
        .commands {
            BrowserCommands(history: history, bookmarks: bookmarks, session: session)
        }

        Settings {
            SettingsView()
        }

        Window("Warren Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 660, height: 580)
    }
}

/// One browser window. Each window owns its own tabs; history and
/// bookmarks are app-wide.
private struct BrowserWindow: View {
    static let sceneID = "browser"

    @StateObject private var store: BrowserStore
    let session: SessionStore
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow

    init(history: HistoryStore, session: SessionStore) {
        _store = StateObject(wrappedValue: BrowserStore(history: history))
        self.session = session
    }

    var body: some View {
        ContentView()
            .environmentObject(store)
            .environmentObject(store.finder)
            // Menu-bar commands act on the frontmost window's store.
            .focusedSceneObject(store)
            .focusedSceneObject(store.finder)
            .background(WindowReader { store.window = $0 })
            .onAppear {
                store.undoManager = undoManager
                session.register(store) { openWindow(id: Self.sceneID) }
            }
            .onChange(of: undoManager) { store.undoManager = undoManager }
            // A link from another app opens in a new tab of this window.
            .onOpenURL { store.openExternal($0) }
    }
}

/// Menu-bar commands. Tab and page commands target the focused window's
/// store and are disabled when no browser window is open.
private struct BrowserCommands: Commands {
    let history: HistoryStore
    let bookmarks: BookmarkStore
    @ObservedObject var session: SessionStore
    @FocusedObject private var store: BrowserStore?
    @FocusedObject private var finder: PageFinder?

    var body: some Commands {
        CommandGroup(replacing: .help) {
            OpenHelpButton()
        }
        // Replaces the text-system Find items, which only target editable
        // text views and would claim ⌘F / ⌘G.
        CommandGroup(replacing: .textEditing) {
            Menu("Find") {
                Button("Find…") { finder?.show() }
                    .keyboardShortcut("f", modifiers: .command)
                    .disabled(finder == nil)
                Button("Find Next") { finder?.findNext() }
                    .keyboardShortcut("g", modifiers: .command)
                    .disabled((finder?.query ?? "").isEmpty)
                Button("Find Previous") { finder?.findPrevious() }
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                    .disabled((finder?.query ?? "").isEmpty)
                Divider()
                Button("Hide Find Bar") { finder?.hide() }
                    .disabled(!(finder?.isVisible ?? false))
            }
        }
        CommandGroup(after: .newItem) {
            NewTabButton(store: store)
            Button("Close Tab") { store?.closeSelectedTab() }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(store == nil)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save as Text…") {
                if let tab = store?.selectedTab { PageExporter.export(tab: tab, format: .plainText) }
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!canExportCurrent)

            Button("Save as Markdown…") {
                if let tab = store?.selectedTab { PageExporter.export(tab: tab, format: .markdown) }
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!canExportCurrent)
        }
        CommandGroup(after: .toolbar) {
            Divider()
            TextSizeCommands()
        }
        CommandMenu("Go") {
            Button("Back") { store?.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!(store?.selectedTab?.canGoBack ?? false))
            Button("Forward") { store?.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!(store?.selectedTab?.canGoForward ?? false))
            Button("Reload Page") { store?.reload() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store?.selectedTab?.currentAddress == nil)
            Divider()
            Button("Home") { store?.goHome() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(store == nil)
            Divider()
            Button("Show Next Tab") { store?.selectNextTab() }
                .keyboardShortcut(.tab, modifiers: .control)
                .disabled((store?.tabs.count ?? 0) < 2)
            Button("Show Previous Tab") { store?.selectPreviousTab() }
                .keyboardShortcut(.tab, modifiers: [.control, .shift])
                .disabled((store?.tabs.count ?? 0) < 2)
        }
        CommandMenu("History") {
            Button("Reopen Closed Tab") { store?.reopenLastClosedTab() }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!(store?.canReopenClosedTab ?? false))
            ReopenSessionButton(session: session)
            Button("Show All History…") { store?.showHistoryManager = true }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(store == nil)
            Divider()
            ForEach(history.items.prefix(15)) { item in
                Button(item.title) {
                    if let address = item.address { store?.open(address, title: item.title) }
                }
                .disabled(store == nil)
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
            Button("Add Bookmark…") { store?.showAddBookmark = true }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(store?.selectedTab?.currentAddress == nil)
            Divider()
            if let store {
                BookmarkMenuItems(nodes: bookmarks.root)
                    .environmentObject(store)
            }
        }
    }

    private var canExportCurrent: Bool {
        guard let tab = store?.selectedTab else { return false }
        return PageExporter.canExport(tab.content)
    }
}

/// New Tab (⌘T) opens a tab in the focused window, or a fresh window
/// when none is open.
private struct NewTabButton: View {
    let store: BrowserStore?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("New Tab") {
            if let store {
                store.newTab()
            } else {
                openWindow(id: BrowserWindow.sceneID)
            }
        }
        .keyboardShortcut("t", modifiers: .command)
    }
}

/// History → Reopen All Windows from Last Session.
private struct ReopenSessionButton: View {
    @ObservedObject var session: SessionStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Reopen All Windows from Last Session") {
            session.restore { openWindow(id: BrowserWindow.sceneID) }
        }
        .disabled(!session.canRestore)
    }
}

/// Hands a view's NSWindow to a closure once the view is in one.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> ReaderView {
        ReaderView(onWindow: onWindow)
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {}

    final class ReaderView: NSView {
        private let onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
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
