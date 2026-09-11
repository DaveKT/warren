import SwiftUI

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                section("What is Gopher?") {
                    Text("""
                    Gopher is an internet protocol from 1991, created at the \
                    University of Minnesota (home of the Golden Gophers) and \
                    standardized as RFC 1436. It predates the web, and it takes a \
                    different view of the internet: instead of pages, Gopherspace \
                    is a giant tree of menus. Every server offers a listing of \
                    items — submenus, text files, images, downloads, searches — \
                    and you burrow from one server to the next.

                    Gopher is still alive. A small, friendly community keeps \
                    hundreds of servers running, full of "phlogs" (gopher blogs), \
                    software archives, and plain-text treasure.
                    """)
                }

                section("Getting around") {
                    Text("""
                    Type an address in the toolbar and press Return. All of these \
                    work:
                    """)
                    bullet("gopher.floodgap.com", detail: "just a host")
                    bullet("gopher://gopher.floodgap.com/1/", detail: "a full gopher URL")
                    bullet("sdf.org:70/1/users", detail: "host, port, and selector")
                    Text("""
                    Click menu items to follow them. Use the ◀ ▶ toolbar buttons \
                    (or ⌘[ and ⌘]) to go back and forward — Warren remembers \
                    where you were scrolled on each page. ⌘R reloads. Open links \
                    in a new tab from their right-click menu, and manage tabs \
                    with ⌘T and ⌘W.
                    """)
                }

                section("Item types") {
                    Text("Every line in a gopher menu has a type that tells Warren what to do when you click it:")
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                        ForEach(HelpItemType.all) { row in
                            GridRow {
                                Image(systemName: row.type.symbolName)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18)
                                Text(String(row.type.rawValue))
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(row.type.label)
                                    .fontWeight(.medium)
                                    .gridColumnAlignment(.leading)
                                Text(row.behavior)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                section("Searching") {
                    Text("""
                    Items marked with a magnifying glass are index searches \
                    (type 7). Click one and Warren asks for your search words, \
                    then shows the results as a menu. The bookmarked \
                    “Veronica-2 Search” searches most of Gopherspace at once.
                    """)
                }

                section("Bookmarks") {
                    Text("""
                    Press ⌘D (or click the bookmark icon) to save the current \
                    page, choosing a title and a folder. Folders nest, and \
                    everything is reachable from the Bookmarks menu, the toolbar \
                    book icon, and the home page. “Manage Bookmarks…” lets you \
                    create folders, rename, move, and remove entries.
                    """)
                }

                section("History") {
                    Text("""
                    Warren records every page you visit. The History menu lists \
                    recent pages; ⌘Y opens the full history with search. You can \
                    remove individual visits, or clear the past hour, 4 hours, \
                    day, or everything.
                    """)
                }

                section("Saving pages") {
                    Text("""
                    Save any menu or text page with ⌘S (plain text) or ⇧⌘S \
                    (Markdown). Markdown export turns menus into link lists, \
                    keeps ASCII art aligned, and preserves the page's source URL.
                    """)
                }

                section("Keyboard shortcuts") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 4) {
                        shortcutRow("⌘T", "New tab")
                        shortcutRow("⌘W", "Close tab")
                        shortcutRow("⌘[  /  ⌘]", "Back / Forward")
                        shortcutRow("⌘R", "Reload page")
                        shortcutRow("⇧⌘H", "Home")
                        shortcutRow("⌘D", "Add bookmark")
                        shortcutRow("⌘Y", "Show history")
                        shortcutRow("⌘S  /  ⇧⌘S", "Save as text / Markdown")
                        shortcutRow("⌘?", "This help")
                    }
                }

                Text("Happy digging! ⛏️")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 24)
            }
            .padding(28)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("⛏️").font(.system(size: 44))
            Text("Warren Help").font(.title.bold())
            Text("A native Gopher browser for macOS")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            content()
        }
    }

    private func bullet(_ code: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(code).font(.system(.body, design: .monospaced))
            Text("— \(detail)").foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
    }

    private func shortcutRow(_ keys: String, _ action: String) -> some View {
        GridRow {
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .gridColumnAlignment(.trailing)
            Text(action).foregroundStyle(.secondary)
        }
    }
}

/// What clicking each item type does, for the help table.
private struct HelpItemType: Identifiable {
    let type: GopherItemType
    let behavior: String
    var id: Character { type.rawValue }

    static let all: [HelpItemType] = [
        .init(type: .menu, behavior: "Opens another menu"),
        .init(type: .textFile, behavior: "Shows a text file"),
        .init(type: .search, behavior: "Asks for search words, shows results"),
        .init(type: .info, behavior: "Plain text on the page — not clickable"),
        .init(type: .gif, behavior: "Shows the image in the tab"),
        .init(type: .image, behavior: "Shows the image in the tab"),
        .init(type: .png, behavior: "Shows the image in the tab"),
        .init(type: .binary, behavior: "Downloads the file"),
        .init(type: .binhex, behavior: "Downloads (BinHex-encoded Mac file)"),
        .init(type: .dosBinary, behavior: "Downloads (DOS archive)"),
        .init(type: .uuencoded, behavior: "Downloads (uuencoded file)"),
        .init(type: .sound, behavior: "Downloads the sound file"),
        .init(type: .document, behavior: "Downloads the document"),
        .init(type: .html, behavior: "Opens web links in your browser"),
        .init(type: .csoServer, behavior: "Phone-book lookup — asks for a query"),
        .init(type: .telnet, behavior: "Hands the session to your telnet app"),
        .init(type: .tn3270, behavior: "Hands the session to your telnet app"),
        .init(type: .redundant, behavior: "A mirror of the previous item"),
        .init(type: .error, behavior: "An error reported by the server"),
    ]
}
