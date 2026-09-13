import SwiftUI
import UniformTypeIdentifiers

struct TabBarView: View {
    @EnvironmentObject private var store: BrowserStore
    @State private var draggedTabID: UUID?

    var body: some View {
        HStack(spacing: 1) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(store.tabs) { tab in
                        TabButton(tab: tab, isSelected: tab.id == store.selectedTabID)
                            .onDrag {
                                draggedTabID = tab.id
                                return NSItemProvider(object: tab.id.uuidString as NSString)
                            } preview: {
                                TabDragPreview(tab: tab)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: TabReorderDelegate(
                                    tabID: tab.id, draggedTabID: $draggedTabID, store: store)
                            )
                    }
                }
            }
            Button(action: { store.newTab() }) {
                Image(systemName: "plus")
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab (⌘T)")
            .padding(.trailing, 4)
        }
        .frame(height: 30)
        .background(.bar)
    }
}

/// The image carried under the cursor while dragging. The live TabButton
/// has a transparent background, so a snapshot of it would let the tabs
/// underneath show through; this stands in with an opaque one.
private struct TabDragPreview: View {
    @ObservedObject var tab: BrowserTab

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(tab.title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .frame(width: 170, height: 30)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Reorders tabs live as the drag passes over each tab slot; the drop
/// itself just ends the drag, since the move already happened.
private struct TabReorderDelegate: DropDelegate {
    let tabID: UUID
    @Binding var draggedTabID: UUID?
    let store: BrowserStore

    func dropEntered(info: DropInfo) {
        guard let draggedTabID, draggedTabID != tabID else { return }
        MainActor.assumeIsolated {
            withAnimation {
                store.moveTab(id: draggedTabID, over: tabID)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        return true
    }
}

private struct TabButton: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var tab: BrowserTab
    let isSelected: Bool
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    /// Gopher Moss #ac7838, from the planned theme palettes; a subtle
    /// fill so the active tab is easy to spot. Dark mode needs a bit
    /// more of it to read against the darker bar.
    private var activeTabTint: Color {
        Color(red: 0xAC / 255, green: 0x78 / 255, blue: 0x38 / 255)
            .opacity(colorScheme == .dark ? 0.32 : 0.22)
    }

    var body: some View {
        HStack(spacing: 6) {
            if tab.isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Text(tab.title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
            Button(action: { store.closeTab(tab) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovering || isSelected ? 1 : 0)
            .help("Close Tab")
        }
        .padding(.horizontal, 10)
        .frame(width: 170, height: 30)
        .background {
            if isSelected {
                Rectangle().fill(.background)
                activeTabTint
            }
        }
        .overlay(alignment: .trailing) { Divider().frame(height: 16) }
        .contentShape(Rectangle())
        .onTapGesture { store.selectTab(tab) }
        .onHover { isHovering = $0 }
    }
}
