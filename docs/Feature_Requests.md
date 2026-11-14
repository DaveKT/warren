# Feature Requests

## Command Line Utility

1. Allow the user to fetch the content from a specific gopher url.
2. Allow the user to list the current bookmarks.
3. Allow the user to list the history items.
4. Allow the user to search bookmarks and history items.
5. Allow the user to remove a specific history item.
6. Allow the user to remove a specific bookmark.
7. Allow the user to remove all history items from the past hour, 4 hours, or all.
8. The CLI should be pipeable to and from other command line utlities (e.g. grep)

## Configuration, History, and Bookmark Syncing

1. Allow users to sync their configuration, history, and bookmarks in iCloud. The user should be the signed-in user for the account (we don't need complex access management). This will allow users with more than one Mac to have their Warren state synced between devices.

## Support for Gemini

Right now, the only protocol supported is Gopher. Gemini is another similar protocol that users of gopher will sometimes run into and use. Warren should support Gemini.

## Automatic Updates

With the current version, the user must take action to update to the latest version of the application. It would be easier if there were a check for updates mechanism so the user could check and install updates without the any extra steps.

## Swipe Navigation

Users of macOS are used to being able to use two fingers to swipe left and right when navigating web pages in Safari. Users of Warren should be able to use the same gestures to navigate pages, both back to return to a previous page and forward to return to a page they just left. This will give us a similar experience to what Mac users are already used to.

**Decision:** match Safari's interactive slide — the page follows the fingers as they swipe, revealing the previous (or next) page underneath, and either completes or snaps back when the fingers lift — rather than simply switching pages once the gesture finishes. This is several times the work of a simple switch but is the experience Mac users expect.

**Notes:**

- Back/Forward already show each history entry's cached content, so the destination page can be shown instantly once the swipe completes; the existing `goBack()` / `goForward()` can drive the actual navigation.
- Horizontal scrolling conflicts with the gesture. Text-file pages don't wrap long lines and scroll sideways, and the image view scrolls in both directions. As in Safari, a swipe should only navigate once the content is already scrolled to that horizontal edge; otherwise the gesture scrolls the content.
- Handle the gesture at the window/content level rather than inside the text view, so it also works on the Home page, error pages, and images.
- Respect the system setting System Settings → Trackpad → More Gestures → "Swipe between pages" (`NSEvent.isSwipeTrackingFromScrollEventsEnabled`), and support Magic Mouse swipes, which arrive the same way.
- Do nothing (or give a small rubber-band bounce) when there is no page to go back or forward to.

## Code Highlighting

Some Gopher pages are dedicated to talking about technical issues, like software development. Those pages may have code snippets to demonstrate a point. Code snippets may be in languages like C, Java, Python, BASH, ZSH, or configuration files like YAML. It would be nice to provide syntax highlighting where code is detected. The highlighting should not interfere with the page formatting. The user should be able to toggle this feature on and off.

**Notes:**

- Detecting code is the hard part: Gopher text has no markup saying where code starts and ends. Proposed phases:
  1. Highlight a whole text file when its selector ends in a known extension (`.c`, `.h`, `.java`, `.py`, `.sh`, `.zsh`, `.yaml`, `.yml`, and so on) or it starts with a `#!` shebang line. Reliable and simple.
  2. Highlight blocks fenced with ` ``` `, which some phlogs use.
  3. Heuristic detection of unmarked code within prose — last, or possibly never, since ASCII art, tables, and columnar layouts are easily mistaken for code.
- Not interfering with formatting means changing color only — no bold, italic, or size changes — so the monospaced columns line up exactly as before.
- Highlighting must coexist with Find on Page. In dark mode Find sets and clears temporary foreground colors across the whole page, so code colors must be applied to the page's attributed text when it is rendered, not as temporary attributes, or Find would wipe them.
- Colors must work in both light and dark mode, ideally drawn from the Gopher palette.
- Copy and Export continue to produce plain text.
- Implementation: the project has no third-party packages. A small built-in tokenizer (keywords, strings, comments, numbers per language) would cover the listed languages and keep it that way; libraries such as Highlightr bundle a JavaScript engine (highlight.js on JavaScriptCore), which is heavy for this.
- Open questions: highlight text-file pages only, or also code in menu pages (which arrives as info lines)? Should it be on or off by default? The toggle would live in the View menu and be remembered between launches.

## History Epic ✅ DONE 2026-09-11

1. ~~Add a feature that can save the browsing history to be easily be called by the user at a later date.~~ History menu + ⌘Y manager with search; persisted across launches.
2. ~~Add a feature to clear the history from the past hour, 4 hours, day, or all.~~ Clear History submenu and manager Clear… menu (clear-all asks for confirmation).
3. ~~Allow the user to remove one or more items from the history individually.~~ Multi-select removal and per-row context menu in the manager.

## Application Help ✅ DONE 2026-09-11

1. ~~Add an application help page(s). The help can explain what gopher is and how to use the app.~~ Help menu → Warren Help (⌘?) opens a dedicated help window: Gopher primer, address formats, item-type reference, searching, bookmarks, history, saving, and keyboard shortcuts.

## Support for Bookmark Folders ✅ DONE 2026-09-11

1. ~~Allow the user to organize and retrieve bookmarks to and from folders in the app.~~ Nestable folders: add sheet picks a destination folder, manager offers new-folder/rename/move-to/remove on an outline view, and folders show as submenus in the Bookmarks menus and on the home page. bookmarks.json is now versioned (v2) with automatic migration.

## Control for Text Sizes ✅ DONE 2026-09-12

1. ~~Include a menu item and keyboard shortcut to increase or decrease the text size of the content window. Control and window text should remain at the default size.~~ View menu: Make Text Bigger (⌘+), Make Text Smaller (⌘−), Actual Size (⌘0). Applies only to page content (menus, text files); the size persists across launches.

## Rearrange Tabs ✅ DONE 2026-09-12

~~In the current version, the tabs can not be rearranged. The user would benefit from being able to reorder the tabs by drag and drop. Additionally, the user would benefit from a keyboard shortcut that would allow them to cycle through the tabs.~~ Tabs reorder live by drag and drop in the tab bar; Go menu → Show Next Tab (⌃⇥) / Show Previous Tab (⌃⇧⇥) cycle through tabs, wrapping at the ends.

## DMG Packaging Script Switch ✅ DONE 2026-09-13

1. ~~Release DMGs are currently created with `hdiutil create`, which macOS now flags as deprecated in favor of `diskutil image create`. Switch the DMG packaging to `diskutil image create` (and script it as part of `Scripts/build-app.sh` or a companion release script) before `hdiutil` is removed in a future macOS release.~~ `Scripts/make-dmg.sh` builds the app and packages it as a compressed (UDZO) versioned DMG with an /Applications drop link, via `diskutil image create from`.

## Color Active Tab ✅ DONE 2026-09-13

~~At the moment there is only a small 'x' on the active tab. This can make it difficult for the user to spot which is the active tab. By adding a subtle fill color to the tab it would be much easier to spot. The color should be in keeping with the gopher theme.~~ The active tab now carries a subtle Gopher Moss (#ac7838) fill, slightly stronger in dark mode so it stays visible.

## Signed Application ✅ DONE 2026-09-13

~~At the moment, the application is unsigned. This requires the user to go through extra steps to provide permissions for the install. Signing would enable direct install and enable other icloud features.~~ Builds are signed with the Developer ID Application certificate (hardened runtime + timestamp) when present, falling back to ad-hoc for dev machines. `make-dmg.sh` signs the DMG, notarizes it with Apple (keychain profile `warren-notary`), staples the ticket, and verifies with Gatekeeper. Bundle ID changed to `app.warren1436.Warren`.

## Command-Z Undo Close Tab ✅ DONE 2026-10-16

~~Today, when a user closes a tab, there is no way to call that same tab and its state (history, etc). Being able to undo a closed tab would be very helpful.~~ ⌘Z (Edit → Undo Close Tab) reopens the most recently closed tab in its original position with its history and cached pages; Redo (⇧⌘Z) closes it again. History → Reopen Closed Tab (⇧⌘T) does the same from the menu. Each window remembers its last 20 closed tabs for the current session only; blank tabs aren't remembered. While typing in the address bar, ⌘Z still undoes typing.

## Command-F Find on Page ✅ DONE 2026-10-16

~~Allowing a user to find text in the active tabs using command F would help users conduct research. The find dialog could include an option to search across all open tabs. Additionally, it could support regex find. It should include both UI and keyboard shortcuts to move to and back from the next instance of the matched string. The find dialog should be minimally intrusive.~~ Edit → Find (⌘F) opens a slim bar under the tab bar, with the search field and controls centered on the page, that highlights matches as you type (the current match in bright yellow; others in a subtle Gopher Moss wash in light mode, and in solid Moss olive #89865b with black text in dark mode for contrast) and scrolls to the current one. ◀ ▶ buttons, ⌘G / ⇧⌘G, and Return / ⇧Return move between matches (wrapping); Esc or Done closes it. Toggles for Match Case (Aa), Regular Expression (.*), and All Tabs — with All Tabs on, Next/Previous step into the next tab with matches, and the count shows how many tabs matched. Works on menus and text files; matches are found within single lines.

## Restore Last Session ✅ DONE 2026-10-25

~~When the app is launched, allow the user to restore their last session — the windows and tabs that were open when Warren last quit, including each tab's back/forward history — similar to Safari's History → Reopen All Windows from Last Session. It could also be offered as a setting to always restore the previous session at launch.~~ History → Reopen All Windows from Last Session reopens the windows open at the last quit, with their tabs, each tab's back/forward history, the selected tab, and window positions; Settings (⌘,) → General → "Reopen windows and tabs from last session when Warren opens" does it at every launch. The session is saved at quit to `session.json` beside the history and bookmarks. Only addresses and titles are saved: the selected tab loads its page right away and the others when first shown, without adding visits to History. Blank tabs and windows are left out, still-blank windows are filled before new ones open, and a session that was never reopened survives a launch-and-quit with nothing open.

## Subtle Accent Colors, Gopher Themes ✅ DONE 2026-10-25

~~At the moment, the UI is monocrome. This should be kept as the default but the user should have the ability to enhance their experience with subtle accent colors chosen from a setting menu. The additional colors should be added sparingly. They should also be adapted when dark mode is selected. Possible color schemes.~~ Settings (⌘,) → Appearance picks the accent colors: Monochrome (the default, Warren's standard look) or one of the three Gopher themes below. A theme colors only the menu links (and the icon of the link under the pointer) and the active tab's fill. Link colors are adjusted per mode to read at 4.5:1 or better against the page: Moss #5d5a2f light / #ced552 dark; Sunset #307995 (a darkened #3e9cbf) light / #3e9cbf dark; Roots #bb525b light / #c77178 (a lightened #bb525b) dark. Active-tab fills: Moss #ac7838, Sunset #f17c37, Roots #b8893d, at the same strength as the original Moss fill. Find highlights keep their own colors in every theme. The choice persists across launches.

**Gopher Moss**

#5d5a2f, #89865b, #ac7838, #ced552, #e9e275

**Gopher Sunset**

#3e9cbf, #a7ecf2, #f2c43d, #f17c37, #f26d50

**Gopher Roots**

#555559, #c9bca4, #bb525b, #b8893d, #92b558

## Image Presentation ✅ DONE 2026-11-14

~~Today, when a user clicks a link in Warren that points to an image (GIF, PNG, or other image types), the image replaces the page in the tab, navigating away from the page that had the link. For this kind of content, navigating away is less user-friendly than showing the image over the page in a lightbox. Instead of replacing the page, clicking an image link would open the image in a lightbox: an overlay on top of the tab's page that dims the page beneath it and is tied to the tab that opened it. It is not a true macOS modal dialog, which would lock the whole window — the tab bar and other tabs stay usable while an image is showing. If the user has an image open and switches to another tab, they see that tab's content without the image; if they switch back to the tab that opened the image, the image is still showing unless they dismissed it. The lightbox stays up until the user dismisses it, and it should have the same look and feel as the rest of Warren.~~ Clicking an image link (g, I, p) on a page opens the image in a lightbox over that tab's page, which dims beneath it, with the link's title and address in a header and Open in New Tab and close buttons. The lightbox lives on the tab (not in its back/forward list) and is drawn inside its content, so the tab bar and other tabs stay usable and each tab keeps or hides its own image as you switch. A spinner shows while the image loads, and an error with Try Again if it fails; Reload refetches the image. Large images shrink to fit; small ones keep their size. Esc, Back (⌘[, the toolbar button — enabled while an image is open, even on a tab's first page — or any future back swipe, which goes through the same Back), ⌘W (File → Close Image), the close button, or a click outside the image close it; navigating the tab closes it too. The visit is recorded in History without a back/forward entry. Images reached any other way — address bar, bookmark, History, or ⌘-click / Open in New Tab (now offered for image links too) — show full-tab. Undo Close Tab and Restore Last Session reopen the page, not the image. Animated GIFs animate in both the lightbox and the full-tab view (NSImageView instead of SwiftUI's Image). Help's item-type table and a new "Viewing images" section describe it.
