# Bug Reports

## Markdown Export Issue ✅ RESOLVED 2026-09-11

The markdown export for gopher://sava.rocks/1/blog/when-the-small-web-gets-an-ai-door/ is not clean. There are several issues.

1. ~~Additional indentation is being introduced causing odd blocking.~~ Fixed: info lines now export as prose; code-indent is reserved for ASCII art.
2. ~~Underline should be rerendered as italics~~ Fixed: rule lines under text italicize the line above.
3. ~~Navigation icons from the original page are being rendered as bullets when they can just be dropped.~~ Fixed: Private Use Area icon glyphs are stripped on export.

Also fixed while in there: `URL:` links now export their real target, duplicated
page titles are dropped, and `* ` info lines become real markdown bullets.

