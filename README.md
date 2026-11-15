# Warren ⛏️

A native Swift/SwiftUI Gopher browser for macOS, implementing the Gopher
protocol as specified in [RFC 1436](https://www.rfc-editor.org/rfc/rfc1436)
with gopher URLs per [RFC 4266](https://www.rfc-editor.org/rfc/rfc4266).

![Warren showing its home page with bookmarks, and a second window browsing the Floodgap gopher menu in tabs](docs/imgs/Warren_Screens.png)

## Install

Download the latest DMG or zip from the
[Releases page](https://github.com/DaveKT/warren/releases), open it,
and drag Warren to the Applications folder. Requires macOS 14+.

The app is Developer ID signed and notarized by Apple, so it opens
directly — no Gatekeeper workarounds needed.

## Features

- **Full RFC 1436 support** — all canonical item types:
  - `0` text files (Lastline `.` stripped, `..` unescaped)
  - `1` menus, `+` redundant servers
  - `2` CSO phone-book servers (query prompt, raw response view)
  - `3` error lines
  - `4`/`5`/`6`/`9` binary types (BinHex, DOS, uuencoded, binary → download)
  - `7` index-search servers (query prompt, TAB-separated search string)
  - `8`/`T` telnet / tn3270 (handed to the system `telnet://` handler)
  - `g`/`I` images shown in a lightbox over the page (animated GIFs play)
  - Plus the de facto extensions `i` (info), `h` (HTML/`URL:` links opened
    in your web browser), `s` (sound), `p` (PNG), `d` (document)
- **Tabs** — ⌘T new tab, ⌘W close tab, per-tab history; drag tabs to
  reorder them, ⌃⇥ / ⌃⇧⇥ cycle through tabs. ⌘Z (or ⇧⌘T) reopens a
  closed tab with its history intact — the last 20 per window, for the
  current session. Each window keeps its own tabs; ⌘-click a link to
  open it in a new tab. Hovering a link shows its type and address at
  the bottom of the window
- **Select and copy** — select any span of page text, across lines and
  links, and copy it as plain text with ⌘C. On menus, paragraphs the
  server sent as hard-wrapped lines are rejoined (ASCII art, lists, and
  links keep their line breaks); right-click → Copy as Shown copies the
  lines exactly
- **Back / Forward / Reload** — ⌘[ , ⌘] , ⌘R, with instant cached history.
  In a tab that started on the home page, Back from the first page
  returns there
- **Swipe between pages** — swipe sideways with two fingers on the
  trackpad (one on a Magic Mouse) to go back and forward, Safari style:
  the page follows your fingers over a picture of the page it's going to,
  then finishes or springs back. Pages that scroll sideways scroll to
  their edge first. With nowhere further to go, the page stretches over a
  field of pickaxes in the accent color. Follows System Settings →
  Trackpad → More Gestures → Swipe between pages
- **Image lightbox** — clicking an image link on a page opens the image
  over the page, which dims beneath it, instead of leaving the page. Each
  tab keeps its own image as you switch tabs, and the rest of the window
  stays usable. Esc, Back (⌘[), ⌘W, the close button, or a click outside
  the image closes it. The visit goes into History but not into the tab's
  back/forward list. Images opened any other way — address bar, bookmark,
  History, or ⌘-click / Open in New Tab — show full-tab; animated GIFs
  play in both
- **Bookmarks** — ⌘D opens an add sheet with title and folder choice;
  nestable folders appear as submenus in the toolbar and menu bar and as
  an outline in the manager (new folder, rename, move, multi-remove).
  Persisted as versioned JSON in
  `~/Library/Application Support/Warren/bookmarks.json` (v1 flat lists
  migrate automatically)
- **History** — every visit recorded to
  `~/Library/Application Support/Warren/history.json`; History menu with
  recent pages, ⌘Y manager with search and per-item removal, and
  clear-by-age (past hour / 4 hours / day / all)
- **Restore Last Session** — History → Reopen All Windows from Last
  Session brings back the windows and tabs open at the last quit, with
  their back/forward history and window positions; Settings → General
  can do it at every launch. Saved to
  `~/Library/Application Support/Warren/session.json`; pages are fetched
  again when each tab is first shown
- **Accent colors** — monochrome by default; Settings → Appearance offers
  Gopher Moss, Sunset, and Roots themes that color links and the active
  tab, with link colors tuned for contrast in light and dark mode
- **Find on Page** — ⌘F opens a slim find bar that highlights matches as
  you type; ⌘G / ⇧⌘G (or Return / ⇧Return) step through them. Options
  for case matching, regular expressions, and searching all tabs in the
  window. In dark mode, matches use a solid, high-contrast highlight
- **Save as TXT / Markdown** — ⌘S / ⇧⌘S; menus become Markdown link lists,
  text pages are fenced to preserve formatting
- **Text size** — ⌘+ / ⌘− / ⌘0 scale page content (chrome stays put);
  the chosen size persists across launches
- **gopher:// link handling** — Warren registers as the system handler,
  so gopher links clicked in Safari, PDFs, or other apps open in a new tab
- **Automatic updates** — Warren → Check for Updates… looks for a newer
  release, shows its notes, and installs it in place. Settings → General
  can check daily and download updates in the background to install when
  Warren quits. Powered by [Sparkle](https://sparkle-project.org); updates
  must be signed with Warren's EdDSA key
- **Help** — ⌘? opens a help window with a Gopher primer, item-type
  reference, and keyboard shortcuts
- UTF-8 with Latin-1 fallback for legacy servers; monospaced rendering so
  Gopherspace ASCII art stays aligned
- Clear connection errors — a refused connection or unknown host is
  reported at once, naming the problem, rather than after a timeout

## Building

Requires macOS 14+ and Xcode command-line tools.

```bash
./Scripts/build-app.sh
open build/Warren.app
```

Or, during development:

```bash
swift build && ./.build/debug/Warren
```

Development runs like this don't check for updates; only the app bundle
does. macOS also treats a bare executable as a background process: its
window takes clicks but not typing, so the address bar won't work. To try
a debug build by hand, put `.build/debug/Warren` and
`.build/debug/Sparkle.framework` in an app bundle (as `build-app.sh` does)
and open that.

## Releasing

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in
   `Scripts/build-app.sh`. Sparkle compares `CFBundleVersion`, so it must
   go up with every release.
2. `./Scripts/make-dmg.sh` builds, signs, and notarizes
   `build/Warren-<version>.dmg`.
3. Make the zip: `xcrun stapler staple build/Warren.app` (the DMG's
   notarization covers the app), then
   `ditto -c -k --keepParent build/Warren.app build/Warren-<version>.zip`.
4. Write the release notes as Markdown, then
   `./Scripts/publish-update.sh notes.md` adds the release to
   `appcast.xml`, signing it with the Sparkle key in the login keychain.
   Run it only after the DMG is stapled: stapling changes its bytes.
5. Push `main` up to the version bump, then create the GitHub
   pre-release `v<version>`, titled "Warren <version>", with the DMG and
   zip attached and the same notes. `gh release create --target` needs
   the full 40-character commit SHA.
6. Commit and push `appcast.xml` last, so the feed never points at a
   missing download. Installed copies find the update at their next
   check.

A notarization error 403 ("A required agreement is missing or has
expired") means a new Apple developer agreement needs accepting.

The Sparkle private key was created once with
`.build/artifacts/sparkle/Sparkle/bin/generate_keys` and must stay backed
up: without it, installed copies can't be sent updates.

## Layout

- `Sources/Warren/Models` — Gopher types, address/URL parsing (RFC 4266),
  menu parser (RFC 1436 §3.8), tab/history state, bookmark store
- `Sources/Warren/Networking` — one-shot TCP transaction client
  (Network.framework)
- `Sources/Warren/Views` — SwiftUI interface; menu and text pages draw
  in an AppKit text view (`PageTextView`) so selection spans the whole
  page and very long files render
- `Sources/Warren/Export` — TXT/Markdown page export
- `Sources/Warren/Updates` — automatic updates (Sparkle)
- `Scripts` — app-bundle assembly, release DMG packaging, and the update
  feed (`appcast.xml`)
- `Resources` — the app icon (`AppIcon.icns`)

## License

Warren's source code is released under the [MIT License](LICENSE).

The license covers the code only. The name "Warren", the Warren app icon,
and the warren1436.app domain are not licensed for use by others: if you
distribute a modified version, please give it a different name and icon so
it isn't mistaken for the official, notarized builds.

Reference material in `docs/refs` is third-party and keeps its own terms:
RFC 1436 is published by the IETF, and the Gopher (protocol) article is
from Wikipedia under [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
