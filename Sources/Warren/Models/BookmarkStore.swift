import Foundation

/// One entry in the bookmark tree: a bookmark (`urlString` set) or a
/// folder (`children` set). The optional `children` doubles as the
/// hierarchy key path for SwiftUI outline lists.
struct BookmarkNode: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var urlString: String? = nil
    var children: [BookmarkNode]? = nil

    var isFolder: Bool { children != nil }
    var address: GopherAddress? { urlString.flatMap(GopherAddress.parse) }

    static func bookmark(title: String, urlString: String) -> BookmarkNode {
        BookmarkNode(title: title, urlString: urlString)
    }

    static func folder(named name: String, children: [BookmarkNode] = []) -> BookmarkNode {
        BookmarkNode(title: name, children: children)
    }
}

@MainActor
final class BookmarkStore: ObservableObject {
    @Published private(set) var root: [BookmarkNode] = []

    private let fileURL: URL

    /// On-disk format, versioned so the CLI and future migrations have
    /// a stable contract. Version 1 was a flat `[Bookmark]` array.
    private struct BookmarkFile: Codable {
        var version: Int
        var items: [BookmarkNode]
    }

    private struct LegacyBookmark: Codable {
        var id: UUID
        var title: String
        var urlString: String
    }

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Warren", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("bookmarks.json")
        load()
        if root.isEmpty { root = Self.starterBookmarks }
    }

    // MARK: - Queries

    func contains(_ address: GopherAddress) -> Bool {
        let url = address.urlString
        return firstNode(in: root) { $0.urlString == url } != nil
    }

    func node(withID id: UUID) -> BookmarkNode? {
        firstNode(in: root) { $0.id == id }
    }

    /// All folders flattened depth-first, with nesting depth for
    /// indented pickers and move menus.
    func flattenedFolders() -> [(id: UUID, name: String, depth: Int)] {
        var result: [(UUID, String, Int)] = []
        func walk(_ nodes: [BookmarkNode], depth: Int) {
            for node in nodes where node.isFolder {
                result.append((node.id, node.title, depth))
                walk(node.children ?? [], depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return result
    }

    // MARK: - Mutations

    func addBookmark(title: String, address: GopherAddress, to folderID: UUID? = nil) {
        guard !contains(address) else { return }
        append(.bookmark(title: title, urlString: address.urlString), to: folderID)
        save()
    }

    @discardableResult
    func addFolder(named name: String, to folderID: UUID? = nil) -> UUID {
        let folder = BookmarkNode.folder(named: name)
        append(folder, to: folderID)
        save()
        return folder.id
    }

    func remove(ids: Set<UUID>) {
        removeAll(in: &root) { ids.contains($0.id) }
        save()
    }

    func remove(address: GopherAddress) {
        let url = address.urlString
        removeAll(in: &root) { $0.urlString == url }
        save()
    }

    func rename(id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        update(id: id, in: &root) { $0.title = trimmed }
        save()
    }

    /// Moves a node to the end of `folderID` (nil = root). Moving a
    /// folder into itself or a descendant is refused.
    func move(id: UUID, to folderID: UUID?) {
        guard id != folderID else { return }
        if let folderID, let moving = node(withID: id), moving.isFolder,
           firstNode(in: moving.children ?? [], where: { $0.id == folderID }) != nil {
            return
        }
        guard let node = extract(id: id, from: &root) else { return }
        if !append(node, to: folderID) {
            root.append(node) // destination vanished; don't lose the node
        }
        save()
    }

    // MARK: - Recursive helpers

    private func firstNode(in nodes: [BookmarkNode],
                           where predicate: (BookmarkNode) -> Bool) -> BookmarkNode? {
        for node in nodes {
            if predicate(node) { return node }
            if let found = firstNode(in: node.children ?? [], where: predicate) {
                return found
            }
        }
        return nil
    }

    @discardableResult
    private func append(_ node: BookmarkNode, to folderID: UUID?) -> Bool {
        guard let folderID else {
            root.append(node)
            return true
        }
        return appendNode(node, toFolder: folderID, in: &root)
    }

    private func appendNode(_ node: BookmarkNode, toFolder folderID: UUID,
                            in nodes: inout [BookmarkNode]) -> Bool {
        for index in nodes.indices {
            if nodes[index].id == folderID, nodes[index].isFolder {
                nodes[index].children!.append(node)
                return true
            }
            if nodes[index].children != nil,
               appendNode(node, toFolder: folderID, in: &nodes[index].children!) {
                return true
            }
        }
        return false
    }

    private func removeAll(in nodes: inout [BookmarkNode],
                           where predicate: (BookmarkNode) -> Bool) {
        nodes.removeAll(where: predicate)
        for index in nodes.indices where nodes[index].children != nil {
            removeAll(in: &nodes[index].children!, where: predicate)
        }
    }

    private func update(id: UUID, in nodes: inout [BookmarkNode],
                        _ body: (inout BookmarkNode) -> Void) {
        for index in nodes.indices {
            if nodes[index].id == id {
                body(&nodes[index])
                return
            }
            if nodes[index].children != nil {
                update(id: id, in: &nodes[index].children!, body)
            }
        }
    }

    private func extract(id: UUID, from nodes: inout [BookmarkNode]) -> BookmarkNode? {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            return nodes.remove(at: index)
        }
        for index in nodes.indices where nodes[index].children != nil {
            if let node = extract(id: id, from: &nodes[index].children!) {
                return node
            }
        }
        return nil
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        if let file = try? decoder.decode(BookmarkFile.self, from: data) {
            root = file.items
        } else if let legacy = try? decoder.decode([LegacyBookmark].self, from: data) {
            // Version 1 flat list: lift into root-level bookmark nodes.
            root = legacy.map { BookmarkNode(id: $0.id, title: $0.title, urlString: $0.urlString) }
            save()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(BookmarkFile(version: 2, items: root)) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static let starterBookmarks: [BookmarkNode] = [
        .bookmark(title: "Floodgap", urlString: "gopher://gopher.floodgap.com/1/"),
        .bookmark(title: "Quux", urlString: "gopher://gopher.quux.org/1/"),
        .bookmark(title: "SDF Public Access UNIX", urlString: "gopher://sdf.org/1/"),
        .bookmark(title: "Veronica-2 Search", urlString: "gopher://gopher.floodgap.com/7/v2/vs"),
    ]
}
