import AppKit
import SwiftUI

/// The slim Find on Page bar shown under the tab bar (⌘F). Return / ⇧Return
/// step through matches, Esc or Done closes it.
struct FindBar: View {
    @ObservedObject var finder: PageFinder
    @FocusState private var fieldFocused: Bool

    private static let doneWidth: CGFloat = 56

    var body: some View {
        HStack(spacing: 0) {
            // Mirrors Done's slot so the controls sit at the true center.
            Color.clear.frame(width: Self.doneWidth, height: 1)
            Spacer(minLength: 8)
            controls
            Spacer(minLength: 8)
            Button("Done") { finder.hide() }
                .frame(width: Self.doneWidth, alignment: .trailing)
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
        .onAppear { focusField() }
        .onChange(of: finder.focusRequest) { focusField() }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            searchField

            ControlGroup {
                Button(action: finder.findPrevious) {
                    Image(systemName: "chevron.left")
                }
                .help("Previous Match (⇧⌘G)")
                Button(action: finder.findNext) {
                    Image(systemName: "chevron.right")
                }
                .help("Next Match (⌘G)")
            }
            .frame(width: 56)
            .disabled(finder.matches.isEmpty)

            Toggle(isOn: $finder.matchesCase) { Text("Aa") }
                .help("Match Case")
            Toggle(isOn: $finder.usesRegex) { Text(".*").monospaced() }
                .help("Regular Expression")
            Toggle("All Tabs", isOn: $finder.searchesAllTabs)
                .help("Search every tab in this window")
        }
    }

    /// A search field with the match count inside its trailing edge, so
    /// the field keeps one width and the centered controls never shift.
    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find on Page", text: $finder.query)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .onSubmit { finder.findNext() }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.shift) else { return .ignored }
                    finder.findPrevious()
                    return .handled
                }
                .onExitCommand { finder.hide() }
            if !status.isEmpty {
                Text(status)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(finder.isPatternInvalid ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 6)
        .frame(width: 300, height: 22)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(fieldFocused ? Color(nsColor: .keyboardFocusIndicatorColor)
                                           : Color(nsColor: .separatorColor),
                              lineWidth: fieldFocused ? 2 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
    }

    private var status: String {
        if finder.query.isEmpty { return "" }
        if finder.isPatternInvalid { return "Invalid pattern" }
        if finder.matches.isEmpty { return "Not found" }
        let total = "\(finder.matches.count)\(finder.hitMatchLimit ? "+" : "")"
        let tabCount = finder.matchedTabCount
        let tabs = finder.searchesAllTabs ? " in \(tabCount) \(tabCount == 1 ? "tab" : "tabs")" : ""
        guard let index = finder.currentIndex else {
            return "None here · \(total)\(tabs)"
        }
        return "\(index + 1) of \(total)\(tabs)"
    }

    /// Focuses the field and selects its text, so ⌘F then typing replaces
    /// the previous query.
    private func focusField() {
        fieldFocused = true
        DispatchQueue.main.async {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }
}
