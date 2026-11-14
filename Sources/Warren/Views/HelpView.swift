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
                    where you were scrolled on each page. ⌘R reloads. Hover over \
                    a link to see its type and address at the bottom of the \
                    window. Open links in a new tab with ⌘-click or from their \
                    right-click menu. Select any text on a page — across as many \
                    lines as you like — and copy it with ⌘C. On menus, Copy \
                    rejoins paragraphs that the server sent as short lines; \
                    Copy as Shown (right-click) keeps every line break. Manage tabs \
                    with ⌘T and ⌘W. Closed a tab by mistake? ⌘Z (or ⇧⌘T) brings \
                    it back with its history — up to the last 20 closed tabs in \
                    each window. Each window (⌘N) keeps its own set of tabs.
                    """)
                }

                section("Viewing images") {
                    Text("""
                    Clicking an image link on a page opens the image right over \
                    the page, which dims behind it, so you never lose your place. \
                    The image belongs to its tab: switch to another tab and it's \
                    out of the way, switch back and it's still there. Close it with \
                    Esc, Back (⌘[ or the ◀ button), ⌘W, the ✕ button, or a click \
                    outside the image. Large images shrink to fit the window; to \
                    see one at full size, open it in a new tab with ⌘-click, its \
                    right-click menu, or the button beside ✕. Images opened from \
                    the address bar, a bookmark, or History also fill the tab. \
                    Animated GIFs play either way, and every image you open is \
                    recorded in History.
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

                    History → Reopen All Windows from Last Session brings back \
                    the windows and tabs that were open when Warren last quit, \
                    each with its Back and Forward history. To do this every \
                    time Warren opens, turn it on in Settings (⌘,) → General.
                    """)
                }

                section("Accent colors") {
                    Text("""
                    Warren is monochrome by default. In Settings (⌘,) → \
                    Appearance you can pick a Gopher theme — Moss, Sunset, or \
                    Roots — which adds a touch of color to links and the active \
                    tab, adjusted for dark mode.
                    """)
                }

                section("Finding text") {
                    Text("""
                    Press ⌘F to search the current page; matches are highlighted \
                    as you type. Return or ⌘G moves to the next match, ⇧Return or \
                    ⇧⌘G to the previous one, and Esc closes the find bar. Aa \
                    matches case, .* treats the search as a regular expression, \
                    and All Tabs searches every tab in the window — Next and \
                    Previous then step from tab to tab.
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
                    HStack(alignment: .top, spacing: 40) {
                        VStack(alignment: .leading, spacing: 18) {
                            shortcutGroup("Tabs & Windows", [
                                ("⌘N", "New window"),
                                ("⌘T", "New tab"),
                                ("⌘W", "Close tab or image"),
                                ("⌘Z", "Undo close tab"),
                                ("⇧⌘T", "Reopen closed tab"),
                                ("⌃⇥", "Next tab"),
                                ("⌃⇧⇥", "Previous tab"),
                            ])
                            shortcutGroup("Navigation", [
                                ("⌘[", "Back or close image"),
                                ("Esc", "Close image"),
                                ("⌘]", "Forward"),
                                ("⌘R", "Reload page"),
                                ("⇧⌘H", "Home"),
                            ])
                            shortcutGroup("Bookmarks & History", [
                                ("⌘D", "Add bookmark"),
                                ("⌘Y", "Show history"),
                            ])
                        }
                        VStack(alignment: .leading, spacing: 18) {
                            shortcutGroup("Find", [
                                ("⌘F", "Find on page"),
                                ("⌘G", "Next match"),
                                ("⇧⌘G", "Previous match"),
                            ])
                            shortcutGroup("Text Size", [
                                ("⌘+", "Make text bigger"),
                                ("⌘−", "Make text smaller"),
                                ("⌘0", "Actual size"),
                            ])
                            shortcutGroup("Saving", [
                                ("⌘S", "Save as text"),
                                ("⇧⌘S", "Save as Markdown"),
                            ])
                            shortcutGroup("Help", [
                                ("⌘?", "Warren Help"),
                                ("⌘,", "Settings"),
                            ])
                        }
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

    /// One titled group of shortcuts. The key column has a fixed width so
    /// keys line up across every group.
    private func shortcutGroup(_ title: String, _ shortcuts: [(keys: String, action: String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(shortcuts, id: \.keys) { shortcut in
                HStack(spacing: 10) {
                    KeyCap(keys: shortcut.keys)
                        .frame(width: 52, alignment: .trailing)
                    Text(shortcut.action)
                }
            }
        }
    }
}

/// A key combination drawn as a small keycap, e.g. ⇧⌘T.
private struct KeyCap: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(.callout.weight(.medium))
            .tracking(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .quaternarySystemFill)))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(nsColor: .separatorColor)))
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
        .init(type: .gif, behavior: "Shows the image over the page (animated GIFs play)"),
        .init(type: .image, behavior: "Shows the image over the page"),
        .init(type: .png, behavior: "Shows the image over the page"),
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
