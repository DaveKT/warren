import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var bookmarks: BookmarkStore
    @EnvironmentObject private var finder: PageFinder
    @FocusState private var addressFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TabBarView()
            Divider()
            if finder.isVisible {
                FindBar(finder: finder)
                Divider()
            }
            if let tab = store.selectedTab {
                TabContentView(tab: tab)
                    .overlay(alignment: .bottomLeading) {
                        if let status = store.linkHoverStatus, tab.lightbox == nil {
                            Text(status)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor)))
                                .padding(6)
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                HomeView()
            }
            if !store.statusMessage.isEmpty {
                Divider()
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
        }
        .toolbar { toolbarContent }
        // The title still names the window (Window menu, Mission Control)
        // but is hidden from the toolbar to leave room for the buttons.
        .toolbarTitleHidden()
        .navigationTitle(store.selectedTab?.title ?? "Warren")
        .sheet(item: $store.searchPrompt) { prompt in
            SearchPromptView(prompt: prompt)
        }
        .sheet(isPresented: $store.showHistoryManager) {
            HistoryView()
        }
        .sheet(isPresented: $store.showAddBookmark) {
            AddBookmarkSheet()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(action: { store.goBack() }) {
                Image(systemName: "chevron.left")
            }
            .help("Back")
            .disabled(!(store.selectedTab?.canGoBack ?? false))

            Button(action: { store.goForward() }) {
                Image(systemName: "chevron.right")
            }
            .help("Forward")
            .disabled(!(store.selectedTab?.canGoForward ?? false))

            Button(action: { store.reload() }) {
                if store.selectedTab?.isLoading == true {
                    Image(systemName: "xmark")
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .help("Reload")
            .disabled(store.selectedTab?.currentAddress == nil)
        }

        ToolbarItem(placement: .principal) {
            TextField("gopher://", text: $store.addressBarText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 280, idealWidth: 460)
                .focused($addressFieldFocused)
                .onSubmit {
                    store.submitAddressBar()
                    addressFieldFocused = false
                }
        }

        // macOS 27 places primary actions right after the address field
        // unless something pushes them to the trailing edge.
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.flexible, placement: .primaryAction)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                bookmarkToggleButton
                BookmarksMenu()
                saveMenu
            }
        }
    }

    private var bookmarkToggleButton: some View {
        let address = store.selectedTab?.currentAddress
        let isBookmarked = address.map { bookmarks.contains($0) } ?? false
        return Button(action: {
            guard let address = store.selectedTab?.currentAddress else { return }
            if isBookmarked {
                bookmarks.remove(address: address)
            } else {
                store.showAddBookmark = true
            }
        }) {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
        }
        .help(isBookmarked ? "Remove Bookmark" : "Add Bookmark")
        .disabled(address == nil)
    }

    private var saveMenu: some View {
        Menu {
            Button("Save as Text…") {
                if let tab = store.selectedTab { PageExporter.export(tab: tab, format: .plainText) }
            }
            Button("Save as Markdown…") {
                if let tab = store.selectedTab { PageExporter.export(tab: tab, format: .markdown) }
            }
        } label: {
            Image(systemName: "square.and.arrow.down")
        }
        .help("Save Page As…")
        .disabled(!(store.selectedTab.map { PageExporter.canExport($0.content) } ?? false))
    }
}

private extension View {
    /// `toolbar(removing: .title)` needs macOS 15; the app deploys to 14.0,
    /// where the title stays visible.
    @ViewBuilder func toolbarTitleHidden() -> some View {
        if #available(macOS 15.0, *) {
            toolbar(removing: .title)
        } else {
            self
        }
    }
}

struct TabContentView: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        ZStack {
            Group {
                switch tab.content {
                case .home:
                    HomeView()
                case .menu, .text:
                    PageTextView(tab: tab, content: tab.content)
                case .image(let data):
                    ImagePageView(data: data, memory: scrollMemory)
                case .error(let message):
                    ErrorPageView(message: message)
                }
            }
            // Fresh identity per navigation so each page gets a new
            // scroll view starting at the top, instead of inheriting
            // the previous page's scroll offset.
            .id("\(tab.historyIndex)|\(tab.currentAddress?.urlString ?? "home")")

            if tab.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            // An image opened from a link on this page, drawn over it.
            if let lightbox = tab.lightbox {
                LightboxView(tab: tab, lightbox: lightbox)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: tab.lightbox?.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Records this page's scroll offset and restores it on Back/Forward.
    private var scrollMemory: ScrollMemory? {
        guard tab.historyIndex >= 0 else { return nil }
        return ScrollMemory(tab: tab, index: tab.historyIndex)
    }
}

struct ErrorPageView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Burrow Blocked", systemImage: "exclamationmark.octagon")
        } description: {
            Text(message)
        }
    }
}
