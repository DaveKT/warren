import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection = Set<UUID>()

    private var filtered: [HistoryItem] { history.search(query) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                TextField("Search history", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(10)
            Divider()

            if filtered.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "No History" : "No Matches",
                    systemImage: "clock",
                    description: Text(query.isEmpty
                        ? "Pages you visit will show up here."
                        : "No visits match “\(query)”."))
                    .frame(maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(filtered) { item in
                        HistoryRow(item: item, open: { open(item) })
                            .tag(item.id)
                    }
                }
            }
            Divider()

            HStack {
                Button(action: removeSelected) {
                    Image(systemName: "minus")
                }
                .disabled(selection.isEmpty)
                .help("Remove selected visits")

                Menu("Clear…") {
                    ForEach(HistoryStore.ClearRange.allCases, id: \.self) { range in
                        Button(range.label) { history.confirmAndClear(range) }
                    }
                }
                .fixedSize()

                Spacer()
                Text("\(filtered.count) visit\(filtered.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                Button("Open") { openSelected() }
                    .disabled(selection.count != 1)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .frame(width: 560, height: 420)
    }

    private func open(_ item: HistoryItem) {
        guard let address = item.address else { return }
        store.open(address, title: item.title)
        dismiss()
    }

    private func openSelected() {
        if let id = selection.first, let item = filtered.first(where: { $0.id == id }) {
            open(item)
        }
    }

    private func removeSelected() {
        history.remove(ids: selection)
        selection.removeAll()
    }
}

private struct HistoryRow: View {
    @EnvironmentObject private var history: HistoryStore
    let item: HistoryItem
    let open: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .lineLimit(1)
                Text(item.urlString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(item.visitedAt.formatted(.relative(presentation: .named)))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: open)
        .contextMenu {
            Button("Open", action: open)
            Button("Copy Gopher URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.urlString, forType: .string)
            }
            Divider()
            Button("Remove from History") {
                history.remove(ids: [item.id])
            }
        }
    }
}
