# Design Changes

## Tool Bar Button Changes ✅ DONE 2026-09-12

~~Currently the Bookmarking, Managing Bookmarks, and Exporting are three separate buttons. Please group them like the back forward and refresh buttons are.~~ The three buttons now sit in a single attached control group on the trailing side of the toolbar.

## Tool Bar Title ✅ DONE 2026-09-12

~~Right now, to the left of the URL field, there is a title. This is not needed. Please remove it to get some space back in the toolbar. The URL field is enough for a user to know where they are. The URL field should remain the same length it is now. One goal is to avoid the overflow icon (>>) when there is not enough space on the toolbar for all the buttons.~~ The toolbar title is hidden on macOS 15+ (the API doesn't exist on macOS 14, where it stays visible); the page title still names the window in the Window menu and Mission Control. The URL field keeps its previous length.
