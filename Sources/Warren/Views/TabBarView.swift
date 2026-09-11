import SwiftUI

struct TabBarView: View {
    @EnvironmentObject private var store: BrowserStore

    var body: some View {
        HStack(spacing: 1) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(store.tabs) { tab in
                        TabButton(tab: tab, isSelected: tab.id == store.selectedTabID)
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

private struct TabButton: View {
    @EnvironmentObject private var store: BrowserStore
    @ObservedObject var tab: BrowserTab
    let isSelected: Bool
    @State private var isHovering = false

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
        .background(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.clear))
        .overlay(alignment: .trailing) { Divider().frame(height: 16) }
        .contentShape(Rectangle())
        .onTapGesture { store.selectTab(tab) }
        .onHover { isHovering = $0 }
    }
}
