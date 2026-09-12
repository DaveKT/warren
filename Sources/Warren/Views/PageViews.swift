import SwiftUI

/// User-adjustable size for page content text, persisted in UserDefaults
/// and adjusted from the View menu (⌘+ / ⌘− / ⌘0).
enum ContentTextSize {
    static let storageKey = "contentTextSize"
    static let `default`: Double = 13
    static let range: ClosedRange<Double> = 9...24
    static let step: Double = 1
}

/// Renders a Gopher menu (type 1 / 7 results). Monospaced throughout so
/// the ASCII art that Gopherspace loves stays aligned.
struct MenuPageView: View {
    @EnvironmentObject private var store: BrowserStore
    let items: [GopherItem]
    var memory: ScrollMemory? = nil

    var body: some View {
        ScrollView([.vertical]) {
            // Plain VStack (not lazy) so the full content height exists
            // immediately and Back/Forward scroll restoration can't be
            // clamped by lazily estimated layout.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    MenuRow(item: item)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(memory)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct MenuRow: View {
    @EnvironmentObject private var store: BrowserStore
    let item: GopherItem
    @State private var isHovering = false
    @AppStorage(ContentTextSize.storageKey) private var textSize = ContentTextSize.default

    var body: some View {
        switch item.type {
        case .info:
            HStack(spacing: 8) {
                Color.clear.frame(width: 16, height: 1)
                Text(item.display.isEmpty ? " " : item.display)
                    .font(.system(size: textSize, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(.vertical, 1)
        case .error:
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .frame(width: 16)
                Text(item.display)
                    .font(.system(size: textSize, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 1)
        default:
            linkRow
        }
    }

    private var linkRow: some View {
        Button(action: { store.open(item: item) }) {
            HStack(spacing: 8) {
                Image(systemName: item.type?.symbolName ?? "questionmark.square.dashed")
                    .foregroundStyle(isHovering ? Color.accentColor : Color.secondary)
                    .frame(width: 16)
                Text(item.display)
                    .font(.system(size: textSize, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .underline(isHovering)
                Text(item.type?.label ?? String(item.typeChar))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .opacity(isHovering ? 1 : 0)
            }
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(item.address?.urlString ?? "")
        .contextMenu {
            if item.type == .menu || item.type == .textFile {
                Button("Open in New Tab") { store.open(item: item, inNewTab: true) }
            }
            if let address = item.address {
                Button("Copy Gopher URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address.urlString, forType: .string)
                }
                Button("Download Linked File…") {
                    store.download(address, suggestedName: item.display)
                }
            }
        }
    }
}

/// Renders a type 0 text file.
struct TextPageView: View {
    let text: String
    var memory: ScrollMemory? = nil
    @AppStorage(ContentTextSize.storageKey) private var textSize = ContentTextSize.default

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text)
                .font(.system(size: textSize, design: .monospaced))
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(memory)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Renders inline images (types g, I, p).
struct ImagePageView: View {
    let data: Data
    var memory: ScrollMemory? = nil

    var body: some View {
        if let image = NSImage(data: data) {
            ScrollView([.vertical, .horizontal]) {
                Image(nsImage: image)
                    .padding(16)
                    .background(memory)
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            ContentUnavailableView("Couldn't decode this image",
                                   systemImage: "photo.badge.exclamationmark")
        }
    }
}

/// The search prompt shown for type 7 (index-search) and type 2 (CSO) items.
struct SearchPromptView: View {
    @EnvironmentObject private var store: BrowserStore
    let prompt: SearchPrompt
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(prompt.itemTitle, systemImage: "magnifyingglass")
                .font(.headline)
            Text("\(prompt.address.host) is asking for search words.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Search words", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel") { store.searchPrompt = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Search", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
    }

    private func submit() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.submitSearch(query: trimmed)
    }
}
