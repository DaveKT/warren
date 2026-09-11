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
                    HomeBookmarkList(nodes: bookmarks.root, depth: 0)
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

/// Recursive bookmark listing for the home page: folders are headers
/// with their contents indented beneath them.
private struct HomeBookmarkList: View {
    @EnvironmentObject private var store: BrowserStore
    let nodes: [BookmarkNode]
    let depth: Int

    var body: some View {
        ForEach(nodes) { node in
            if node.isFolder {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(node.title)
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.leading, CGFloat(depth) * 20 + 10)
                HomeBookmarkList(nodes: node.children ?? [], depth: depth + 1)
            } else {
                Button(action: {
                    if let address = node.address {
                        store.open(address, title: node.title)
                    }
                }) {
                    HStack {
                        Image(systemName: "bookmark")
                            .foregroundStyle(.secondary)
                        Text(node.title)
                        Spacer()
                        if let url = node.urlString {
                            Text(url)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                .padding(.leading, CGFloat(depth) * 20)
            }
        }
    }
}
