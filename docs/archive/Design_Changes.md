# Design Changes

> **Archived 2026-11-15.** Open bugs, feature requests, and design changes are now tracked in [GitHub Issues](https://github.com/DaveKT/warren/issues). This file is kept as a record of finished work; items that were still open link to their issues.

## Tool Bar Button Changes ✅ DONE 2026-09-12

~~Currently the Bookmarking, Managing Bookmarks, and Exporting are three separate buttons. Please group them like the back forward and refresh buttons are.~~ The three buttons now sit in a single attached control group on the trailing side of the toolbar.

## Tool Bar Title ✅ DONE 2026-09-12

~~Right now, to the left of the URL field, there is a title. This is not needed. Please remove it to get some space back in the toolbar. The URL field is enough for a user to know where they are. The URL field should remain the same length it is now. One goal is to avoid the overflow icon (>>) when there is not enough space on the toolbar for all the buttons.~~ The toolbar title is hidden on macOS 15+ (the API doesn't exist on macOS 14, where it stays visible); the page title still names the window in the Window menu and Mission Control. The URL field keeps its previous length.

## New App Icon ✅ DONE 2026-10-17

~~Replace the app icon with the new Warren "W" icon.~~ The icon now ships as `Resources/AppIcon.icns` (all ten standard sizes) and the build copies it into the app; the old icon generated from an emoji is gone.

## Link Hover Feedback ✅ DONE 2026-10-17

~~When menu pages moved to a single selectable text view, hovering a link could no longer show the small item-type label beside it (or the address tooltip).~~ Hovering a link now underlines it, tints its icon, and shows its type and address — e.g. "Image · gopher://…" — in a small label at the bottom of the window.

## Find Highlight Contrast in Dark Mode ✅ DONE 2026-10-17

~~In dark mode, find matches other than the current one were hard to see: the moss highlight stood out from the page at only 1.6:1, and blue link text on it was 2.7:1.~~ Dark mode now highlights those matches in solid Moss olive (#89865b) with black text — 4.5:1 against the page and 5.6:1 for the text, still distinct from the yellow current match. Light mode is unchanged, and find now has its own color, separate from the active tab's.
