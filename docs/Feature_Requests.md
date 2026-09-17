# Feature Requests

## History Epic ✅ DONE 2026-09-11

1. ~~Add a feature that can save the browsing history to be easily be called by the user at a later date.~~ History menu + ⌘Y manager with search; persisted across launches.
2. ~~Add a feature to clear the history from the past hour, 4 hours, day, or all.~~ Clear History submenu and manager Clear… menu (clear-all asks for confirmation).
3. ~~Allow the user to remove one or more items from the history individually.~~ Multi-select removal and per-row context menu in the manager.

## Application Help ✅ DONE 2026-09-11

1. ~~Add an application help page(s). The help can explain what gopher is and how to use the app.~~ Help menu → Warren Help (⌘?) opens a dedicated help window: Gopher primer, address formats, item-type reference, searching, bookmarks, history, saving, and keyboard shortcuts.

## Command Line Utility

1. Allow the user to fetch the content from a specific gopher url.
2. Allow the user to list the current bookmarks.
3. Allow the user to list the history items.
4. Allow the user to search bookmarks and history items.
5. Allow the user to remove a specific history item.
6. Allow the user to remove a specific bookmark.
7. Allow the user to remove all history items from the past hour, 4 hours, or all.
8. The CLI should be pipeable to and from other command line utlities (e.g. grep)

## Support for Bookmark Folders ✅ DONE 2026-09-11

1. ~~Allow the user to organize and retrieve bookmarks to and from folders in the app.~~ Nestable folders: add sheet picks a destination folder, manager offers new-folder/rename/move-to/remove on an outline view, and folders show as submenus in the Bookmarks menus and on the home page. bookmarks.json is now versioned (v2) with automatic migration.

## Control for Text Sizes ✅ DONE 2026-09-12

1. ~~Include a menu item and keyboard shortcut to increase or decrease the text size of the content window. Control and window text should remain at the default size.~~ View menu: Make Text Bigger (⌘+), Make Text Smaller (⌘−), Actual Size (⌘0). Applies only to page content (menus, text files); the size persists across launches.

## Configuration, History, and Bookmark Syncing

1. Allow users to sync their configuration, history, and bookmarks in iCloud. The user should be the signed-in user for the account (we don't need complex access management). This will allow users with more than one Mac to have their Warren state synced between devices.

## Support for Gemini

Right now, the only protocol supported is Gopher. Gemini is another similar protocol that users of gopher will sometimes run into and use. Warren should support Gemini.

## DMG Packaging Script Switch ✅ DONE 2026-09-13

1. ~~Release DMGs are currently created with `hdiutil create`, which macOS now flags as deprecated in favor of `diskutil image create`. Switch the DMG packaging to `diskutil image create` (and script it as part of `Scripts/build-app.sh` or a companion release script) before `hdiutil` is removed in a future macOS release.~~ `Scripts/make-dmg.sh` builds the app and packages it as a compressed (UDZO) versioned DMG with an /Applications drop link, via `diskutil image create from`.

## Rearrange Tabs ✅ DONE 2026-09-12

~~In the current version, the tabs can not be rearranged. The user would benefit from being able to reorder the tabs by drag and drop. Additionally, the user would benefit from a keyboard shortcut that would allow them to cycle through the tabs.~~ Tabs reorder live by drag and drop in the tab bar; Go menu → Show Next Tab (⌃⇥) / Show Previous Tab (⌃⇧⇥) cycle through tabs, wrapping at the ends.

## Subtle Accent Colors, Gopher Themes

At the moment, the UI is monocrome. This should be kept as the default but the user should have the ability to enhance their experience with subtle accent colors chosen from a setting menu. The additional colors should be added sparingly. They should also be adapted when dark mode is selected. Possible color schemes.

**Gopher Moss**

#5d5a2f, #89865b, #ac7838, #ced552, #e9e275

**Gopher Sunset**

#3e9cbf, #a7ecf2, #f2c43d, #f17c37, #f26d50

**Gopher Roots**

#555559, #c9bca4, #bb525b, #b8893d, #92b558

### Color Active Tab ✅ DONE 2026-09-13

~~At the moment there is only a small 'x' on the active tab. This can make it difficult for the user to spot which is the active tab. By adding a subtle fill color to the tab it would be much easier to spot. The color should be in keeping with the gopher theme.~~ The active tab now carries a subtle Gopher Moss (#ac7838) fill, slightly stronger in dark mode so it stays visible.

## Signed Application ✅ DONE 2026-09-13

~~At the moment, the application is unsigned. This requires the user to go through extra steps to provide permissions for the install. Signing would enable direct install and enable other icloud features.~~ Builds are signed with the Developer ID Application certificate (hardened runtime + timestamp) when present, falling back to ad-hoc for dev machines. `make-dmg.sh` signs the DMG, notarizes it with Apple (keychain profile `warren-notary`), staples the ticket, and verifies with Gatekeeper. Bundle ID changed to `app.warren1436.Warren`.

## Automatic Updates

With the current version, the user must take action to update to the latest version of the application. It would be easier if there were a check for updates mechanism so the user could check and install updates without the any extra steps.

## Command-Z Undo Close Tab

Today, when a user closes a tab, there is no way to call that same tab and its state (history, etc). Being able to undo a closed tab would be very helpful. 

## Command-F Find on Page

Allowing a user to find text in the active tabs using command F would help users conduct research. The find dialog could include an option to search across all open tabs. Additionally, it could support regex find. It should include both UI and keyboard shortcuts to move to and back from the next instance of the matched string. The find dialog should be minimally intrusive.


