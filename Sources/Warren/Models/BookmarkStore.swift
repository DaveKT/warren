import Foundation

struct Bookmark: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var urlString: String

    var address: GopherAddress? { GopherAddress.parse(urlString) }
}

@MainActor
final class BookmarkStore: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []

    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Warren", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("bookmarks.json")
        load()
        if bookmarks.isEmpty { bookmarks = Self.starterBookmarks }
    }

    func contains(_ address: GopherAddress) -> Bool {
        let url = address.urlString
        return bookmarks.contains { $0.urlString == url }
    }

    func add(title: String, address: GopherAddress) {
        guard !contains(address) else { return }
        bookmarks.append(Bookmark(title: title, urlString: address.urlString))
        save()
    }

    func remove(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        save()
    }

    func remove(address: GopherAddress) {
        let url = address.urlString
        bookmarks.removeAll { $0.urlString == url }
        save()
    }

    func rename(_ bookmark: Bookmark, to title: String) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index].title = title
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        bookmarks.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        bookmarks = (try? JSONDecoder().decode([Bookmark].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(bookmarks) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static let starterBookmarks: [Bookmark] = [
        Bookmark(title: "Floodgap", urlString: "gopher://gopher.floodgap.com/1/"),
        Bookmark(title: "Quux", urlString: "gopher://gopher.quux.org/1/"),
        Bookmark(title: "SDF Public Access UNIX", urlString: "gopher://sdf.org/1/"),
        Bookmark(title: "Veronica-2 Search", urlString: "gopher://gopher.floodgap.com/7/v2/vs"),
    ]
}
