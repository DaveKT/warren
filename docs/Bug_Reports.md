# Bug Reports

## Markdown Export Issue ✅ RESOLVED 2026-09-11

The markdown export for gopher://sava.rocks/1/blog/when-the-small-web-gets-an-ai-door/ is not clean. There are several issues.

1. ~~Additional indentation is being introduced causing odd blocking.~~ Fixed: info lines now export as prose; code-indent is reserved for ASCII art.
2. ~~Underline should be rerendered as italics~~ Fixed: rule lines under text italicize the line above.
3. ~~Navigation icons from the original page are being rendered as bullets when they can just be dropped.~~ Fixed: Private Use Area icon glyphs are stripped on export.

Also fixed while in there: `URL:` links now export their real target, duplicated
page titles are dropped, and `* ` info lines become real markdown bullets.

## Link from External Source not Working Correctly ✅ RESOLVED 2026-09-12

~~When clicking on a gopher link in an external application like Safari or a PDF, macOS correctly offers to open the link in Warren. Warren will open a new window and the page will be the current page open, not the link clicked. Expected behavior is a new tab will open (not a new window) to the link clicked in the external application.~~ Fixed: the app never handled the URL macOS handed it, so SwiftUI just spawned a fresh window. gopher:// links from other apps now open in a new tab of the existing window.

## Windows Mirror Each Other ✅ RESOLVED 2026-10-16

~~Every window shared a single set of tabs: opening a second window (⌘N) showed the same tabs and the same selected tab as the first, and actions in one window changed the other.~~ Fixed: each window now owns its own tabs and navigation state, and menu-bar commands act on the frontmost window (disabled when no window is open; ⌘T then opens a new window). History and bookmarks remain shared app-wide. A gopher:// link that arrives when macOS creates a fresh window now loads into that window's blank tab instead of opening beside it.

## Toolbar Buttons Drift Next to the URL Field on macOS 27 ✅ RESOLVED 2026-10-16

~~On macOS 27, the bookmark / bookmarks-menu / export button group sits immediately after the URL field instead of at the trailing edge of the toolbar, leaving an empty gap on the right.~~ Fixed: macOS 27 no longer pushes primary-action toolbar items to the trailing edge on its own; a flexible toolbar spacer (macOS 26+) now does, restoring the original layout. The toolbar code hadn't changed — this came with the OS update.

## Very Large Text Files Render Blank

Text files beyond roughly 10,000 lines (e.g. the 653 KB `gopher://gopher.quux.org/0/Archives/mirrors/wiretap.area.com/Gov/npr.txt`) fetch successfully and the tab title updates, but the page area stays blank: a text page is one SwiftUI `Text`, and a single text layer that tall silently fails to draw. Files of a few thousand lines (a 169 KB act of Congress) render fine. Predates 1.4b. The same single-`Text` design is why Find highlights on long pages are expensive — SwiftUI `Text` slows sharply with thousands of attributed runs, which is why 1.4b highlights only the lines around the current match once a page has more than 500 matches. The fix for both is a TextKit-backed (`NSTextView`) text page, which handles arbitrary length and attributed ranges cheaply.
