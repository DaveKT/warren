import SwiftUI

/// Recursive menu items for a bookmark tree: folders become submenus.
/// Used by both the toolbar menu and the menu-bar Bookmarks menu.
struct BookmarkMenuItems: View {
    @EnvironmentObject private var store: BrowserStore
    let nodes: [BookmarkNode]

    var body: some View {
        ForEach(nodes) { node in
            if node.isFolder {
                Menu(node.title) {
                    if let children = node.children, !children.isEmpty {
                        BookmarkMenuItems(nodes: children)
                    } else {
                        Text("Empty").foregroundStyle(.secondary)
                    }
                }
            } else {
                Button(node.title) {
                    if let address = node.address {
                        store.open(address, title: node.title)
                    }
                }
            }
        }
    }
}

/// Toolbar menu for browsing and managing bookmarks.
struct BookmarksMenu: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var bookmarks: BookmarkStore
    @State private var showManager = false

    var body: some View {
        Menu {
            BookmarkMenuItems(nodes: bookmarks.root)
            if !bookmarks.root.isEmpty { Divider() }
            Button("Manage Bookmarks…") { showManager = true }
        } label: {
            Image(systemName: "book")
        }
        .help("Bookmarks")
        .sheet(isPresented: $showManager) {
            BookmarkManagerView()
        }
    }
}

/// Sheet for adding the current page as a bookmark: title + destination folder.
struct AddBookmarkSheet: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var bookmarks: BookmarkStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var folderID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add Bookmark", systemImage: "bookmark")
                .font(.headline)
            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .frame(width: 340)
            Picker("Folder:", selection: $folderID) {
                Text("Bookmarks (top level)").tag(UUID?.none)
                ForEach(bookmarks.flattenedFolders(), id: \.id) { folder in
                    Text(String(repeating: "    ", count: folder.depth) + "📁 " + folder.name)
                        .tag(UUID?.some(folder.id))
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(store.selectedTab?.currentAddress == nil
                              || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .onAppear { title = store.selectedTab?.title ?? "" }
    }

    private func add() {
        guard let address = store.selectedTab?.currentAddress else { return }
        bookmarks.addBookmark(
            title: title.trimmingCharacters(in: .whitespaces),
            address: address, to: folderID)
        dismiss()
    }
}

struct BookmarkManagerView: View {
    @EnvironmentObject private var bookmarks: BookmarkStore
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    @State private var selection = Set<UUID>()
    @State private var renaming: BookmarkNode?
    @State private var renameText = ""

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                OutlineGroup(bookmarks.root, children: \.children) { node in
                    row(node).tag(node.id)
                }
            }
            .frame(minHeight: 300)
            Divider()
            HStack {
                Button(action: newFolder) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("New folder (inside the selected folder, if any)")

                Button(action: removeSelected) {
                    Image(systemName: "minus")
                }
                .disabled(selection.isEmpty)
                .help("Remove selected")

                Button("Rename…") { beginRename() }
                    .disabled(selection.count != 1)

                moveMenu

                Spacer()
                Button("Open") { openSelected() }
                    .disabled(!(singleSelectedNode?.isFolder == false))
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(width: 520, height: 400)
        .alert("Rename", isPresented: renameBinding, presenting: renaming) { node in
            TextField("Name", text: $renameText)
            Button("Rename") {
                bookmarks.rename(id: node.id, to: renameText)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func row(_ node: BookmarkNode) -> some View {
        HStack {
            Image(systemName: node.isFolder ? "folder" : "bookmark")
                .foregroundStyle(node.isFolder ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                if let url = node.urlString {
                    Text(url)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var moveMenu: some View {
        Menu("Move To") {
            Button("Bookmarks (top level)") { moveSelected(to: nil) }
            ForEach(bookmarks.flattenedFolders(), id: \.id) { folder in
                if !selection.contains(folder.id) {
                    Button(String(repeating: "    ", count: folder.depth) + folder.name) {
                        moveSelected(to: folder.id)
                    }
                }
            }
        }
        .fixedSize()
        .disabled(selection.isEmpty)
    }

    private var singleSelectedNode: BookmarkNode? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return bookmarks.node(withID: id)
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func beginRename() {
        guard let node = singleSelectedNode else { return }
        renameText = node.title
        renaming = node
    }

    private func newFolder() {
        let parent = singleSelectedNode?.isFolder == true ? singleSelectedNode?.id : nil
        let id = bookmarks.addFolder(named: "New Folder", to: parent)
        selection = [id]
        beginRename()
    }

    private func removeSelected() {
        bookmarks.remove(ids: selection)
        selection.removeAll()
    }

    private func moveSelected(to folderID: UUID?) {
        for id in selection {
            bookmarks.move(id: id, to: folderID)
        }
    }

    private func openSelected() {
        if let node = singleSelectedNode, let address = node.address {
            store.open(address, title: node.title)
            dismiss()
        }
    }
}
