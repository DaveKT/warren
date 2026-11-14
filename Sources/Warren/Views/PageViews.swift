import SwiftUI

/// User-adjustable size for page content text, persisted in UserDefaults
/// and adjusted from the View menu (⌘+ / ⌘− / ⌘0).
enum ContentTextSize {
    static let storageKey = "contentTextSize"
    static let `default`: Double = 13
    static let range: ClosedRange<Double> = 9...24
    static let step: Double = 1
}

/// Renders an image (types g, I, p) full-tab, at its own size, when it's
/// opened from the address bar, a bookmark, History, or in a new tab.
/// Images clicked on a page open in a `LightboxView` instead.
struct ImagePageView: View {
    let data: Data
    var memory: ScrollMemory? = nil

    var body: some View {
        if let image = NSImage(data: data) {
            ScrollView([.vertical, .horizontal]) {
                AnimatedImage(image: image)
                    .frame(width: image.size.width, height: image.size.height)
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
