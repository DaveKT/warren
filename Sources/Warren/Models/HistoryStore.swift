import AppKit
import Foundation

struct HistoryItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var urlString: String
    var title: String
    var visitedAt: Date

    var address: GopherAddress? { GopherAddress.parse(urlString) }
}

@MainActor
final class HistoryStore: ObservableObject {
    /// Newest first.
    @Published private(set) var items: [HistoryItem] = []

    private let fileURL: URL
    private let maxItems = 5000

    init() {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = support.appendingPathComponent("Warren", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    /// Records a visit. A repeat of the most recent URL refreshes it in
    /// place instead of stacking duplicates.
    func record(address: GopherAddress, title: String) {
        let url = address.urlString
        if let first = items.first, first.urlString == url {
            items[0].visitedAt = Date()
            items[0].title = title
        } else {
            items.insert(HistoryItem(urlString: url, title: title, visitedAt: Date()), at: 0)
            if items.count > maxItems {
                items.removeLast(items.count - maxItems)
            }
        }
        save()
    }

    /// Loads often resolve a better title after the visit was recorded.
    func updateTitle(for address: GopherAddress, title: String) {
        let url = address.urlString
        guard let index = items.firstIndex(where: { $0.urlString == url }) else { return }
        items[index].title = title
        save()
    }

    func remove(ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    enum ClearRange: CaseIterable {
        case pastHour, past4Hours, pastDay, all

        var label: String {
            switch self {
            case .pastHour: return "Past Hour"
            case .past4Hours: return "Past 4 Hours"
            case .pastDay: return "Past Day"
            case .all: return "All History"
            }
        }

        var interval: TimeInterval? {
            switch self {
            case .pastHour: return 3600
            case .past4Hours: return 4 * 3600
            case .pastDay: return 24 * 3600
            case .all: return nil
            }
        }
    }

    /// Removes visits made within the range (browser-style "clear the
    /// past hour"), or everything for `.all`.
    func clear(_ range: ClearRange) {
        if let interval = range.interval {
            let cutoff = Date().addingTimeInterval(-interval)
            items.removeAll { $0.visitedAt >= cutoff }
        } else {
            items.removeAll()
        }
        save()
    }

    /// `.all` is irreversible enough to deserve a confirmation.
    func confirmAndClear(_ range: ClearRange) {
        guard range == .all else {
            clear(range)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Clear all history?"
        alert.informativeText = "This removes every recorded visit and cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear All History")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            clear(.all)
        }
    }

    func search(_ query: String) -> [HistoryItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.urlString.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([HistoryItem].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(items) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
