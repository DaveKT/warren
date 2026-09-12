# Feature Requests

## History Epic ✅ DONE 2026-09-11

1. ~~Add a feature that can save the browsing history to be easily be called by the user at a later date.~~ History menu + ⌘Y manager with search; persisted across launches.
2. ~~Add a feature to clear the history from the past hour, 4 hours, day, or all.~~ Clear History submenu and manager Clear… menu (clear-all asks for confirmation).
3. ~~All the user to remove one or more items from the history individually.~~ Multi-select removal and per-row context menu in the manager.

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

1. ~~All the user to organize and retrieve bookmarks to and from folders in the app.~~ Nestable folders: add sheet picks a destination folder, manager offers new-folder/rename/move-to/remove on an outline view, and folders show as submenus in the Bookmarks menus and on the home page. bookmarks.json is now versioned (v2) with automatic migration.

## Control for Text Sizes

1. Include a menu item and keyboard shortcut to increase or decrease the text size of the content window. Control and window text should remain at the default size.

## Configuration, History, and Bookmark Syncing

1. Allow users to sync their configuration, history, and booksmarks in icloud. The user should be the signed in user for the account (we don't need complex access management). This will allow users with more than one max to haev their Warren state sync'd between devices.

## Support for Gemini

Right now, the only protocol supported is Gopher. Gemini is another similar protocol that users of gopher will sometimes run into and use. Warren should support Gemini.