import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var bookmarks: BookmarkStore

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("⛏️")
                        .font(.system(size: 56))
                    Text("Warren")
                        .font(.largeTitle.bold())
                    Text("A burrow into Gopherspace · RFC 1436")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 48)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Bookmarks")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    ForEach(bookmarks.bookmarks) { bookmark in
                        Button(action: {
                            if let address = bookmark.address {
                                store.open(address, title: bookmark.title)
                            }
                        }) {
                            HStack {
                                Image(systemName: "bookmark")
                                    .foregroundStyle(.secondary)
                                Text(bookmark.title)
                                Spacer()
                                Text(bookmark.urlString)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .frame(maxWidth: 520)

                Text("Type an address like gopher.floodgap.com in the bar above, or pick a bookmark to start digging.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Toolbar menu for browsing and managing bookmarks.
struct BookmarksMenu: View {
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var bookmarks: BookmarkStore
    @State private var showManager = false

    var body: some View {
        Menu {
            ForEach(bookmarks.bookmarks) { bookmark in
                Button(bookmark.title) {
                    if let address = bookmark.address {
                        store.open(address, title: bookmark.title)
                    }
                }
            }
            if !bookmarks.bookmarks.isEmpty { Divider() }
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

struct BookmarkManagerView: View {
    @EnvironmentObject private var bookmarks: BookmarkStore
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Bookmark.ID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(bookmarks.bookmarks) { bookmark in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bookmark.title)
                        Text(bookmark.urlString)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .tag(bookmark.id)
                }
                .onMove { source, destination in
                    bookmarks.move(fromOffsets: source, toOffset: destination)
                }
            }
            .frame(minHeight: 260)
            Divider()
            HStack {
                Button(action: removeSelected) {
                    Image(systemName: "minus")
                }
                .disabled(selection == nil)
                .help("Remove selected bookmark")
                Spacer()
                Button("Open") { openSelected() }
                    .disabled(selection == nil)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(width: 460, height: 340)
    }

    private func removeSelected() {
        if let selected = bookmarks.bookmarks.first(where: { $0.id == selection }) {
            bookmarks.remove(selected)
            selection = nil
        }
    }

    private func openSelected() {
        if let selected = bookmarks.bookmarks.first(where: { $0.id == selection }),
           let address = selected.address {
            store.open(address, title: selected.title)
            dismiss()
        }
    }
}
