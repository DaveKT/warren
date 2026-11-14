import AppKit
import SwiftUI

/// A menu or text-file page in a read-only, selectable AppKit text view.
/// The whole page is one document, so a selection can run across any lines
/// (SwiftUI can't select across separate Text views), very long pages draw
/// (SwiftUI's Text silently fails on huge ones), and find highlights are
/// cheap temporary attributes rather than restyled text.
///
/// Menu links are `.link` attributes that open their item when clicked; the
/// item-type icons are drawn in a left gutter so they're never selected or
/// copied.
struct PageTextView: NSViewRepresentable {
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var store: BrowserStore
    @EnvironmentObject private var finder: PageFinder
    let content: TabContent
    @AppStorage(ContentTextSize.storageKey) private var textSize = ContentTextSize.default
    @AppStorage(Theme.storageKey) private var theme = Theme.monochrome

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab, historyIndex: tab.historyIndex)
    }

    func makeNSView(context: Context) -> NSScrollView {
        if case .menu = content {
            return context.coordinator.makeScrollView(isMenu: true)
        }
        return context.coordinator.makeScrollView(isMenu: false)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.store = store
        coordinator.apply(theme)
        coordinator.show(content, textSize: textSize)
        coordinator.setCovered(tab.lightbox != nil)
        coordinator.applyHighlights(from: finder)
        coordinator.revealPendingMatch(from: finder)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var store: BrowserStore?
        private let tab: BrowserTab
        private let historyIndex: Int
        private var scrollView: NSScrollView?
        private var textView: PageNSTextView?
        private var document: PageDocument?
        private var shownContent: TabContent?
        private var shownTextSize: Double?
        private var shownTheme: Theme?
        private var appliedHighlightsVersion: Int?
        private var appliedCurrent: FindMatch?
        private var appliedDarkText: Bool?
        private weak var finder: PageFinder?
        private var scrollObserver: NSObjectProtocol?
        private var didRestoreScroll = false

        /// Menu text starts this far in, leaving room for the type icon.
        static let gutterWidth: CGFloat = 24
        private static let itemURLScheme = "warren-item"

        init(tab: BrowserTab, historyIndex: Int) {
            self.tab = tab
            self.historyIndex = historyIndex
        }

        func makeScrollView(isMenu: Bool) -> NSScrollView {
            // Menus wrap to the window like before; text files keep their
            // line breaks and scroll sideways.
            let wraps = isMenu
            // Contiguous layout (the default): non-contiguous layout opens
            // huge pages slightly faster but only estimates the position of
            // text it hasn't laid out, so Back/Forward scroll restoration
            // and scroll-to-match land several lines off.
            let storage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            storage.addLayoutManager(layoutManager)
            let unbounded = CGFloat.greatestFiniteMagnitude
            let container = GutterTextContainer(size: NSSize(width: wraps ? 0 : unbounded, height: unbounded))
            container.gutterWidth = isMenu ? Self.gutterWidth : 0
            container.widthTracksTextView = wraps
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)

            let textView = PageNSTextView(frame: .zero, textContainer: container)
            textView.delegate = self
            textView.isEditable = false
            textView.isSelectable = true
            textView.allowsUndo = false
            textView.usesFindBar = false
            // No spelling, grammar, or data detection on read-only pages.
            textView.enabledTextCheckingTypes = 0
            textView.isContinuousSpellCheckingEnabled = false
            textView.isGrammarCheckingEnabled = false
            textView.isAutomaticLinkDetectionEnabled = false
            textView.drawsBackground = true
            textView.backgroundColor = .textBackgroundColor
            textView.textContainerInset = NSSize(width: 16, height: isMenu ? 12 : 16)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = !wraps
            textView.autoresizingMask = wraps ? [.width] : []
            textView.minSize = .zero
            textView.maxSize = NSSize(width: unbounded, height: unbounded)
            textView.onHoverLine = { [weak self] line in self?.hoverChanged(to: line) }
            textView.menuForLine = { [weak self] line in self?.linkMenu(forLine: line) }
            // Match text color depends on light/dark, so a mode switch while
            // a search is showing re-applies the highlights.
            textView.onAppearanceChange = { [weak self] in
                guard let self, let finder = self.finder else { return }
                self.applyHighlights(from: finder)
            }

            let scrollView = NSScrollView()
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = !wraps
            scrollView.autohidesScrollers = true
            scrollView.drawsBackground = true
            scrollView.backgroundColor = .textBackgroundColor
            scrollView.documentView = textView

            self.scrollView = scrollView
            self.textView = textView
            observeScroll()
            return scrollView
        }

        func tearDown() {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
            scrollObserver = nil
            if textView?.hoveredLine != nil { store?.linkHoverStatus = nil }
        }

        /// An image lightbox is showing over the page.
        func setCovered(_ covered: Bool) {
            textView?.isCovered = covered
        }

        /// Link colors come from the accent theme (Settings → Appearance).
        func apply(_ theme: Theme) {
            guard let textView, theme != shownTheme else { return }
            shownTheme = theme
            textView.linkTextAttributes = [
                .foregroundColor: theme.linkColor,
                .cursor: NSCursor.pointingHand,
            ]
            textView.hoverColor = theme.linkColor
            if let length = textView.textStorage?.length, length > 0 {
                textView.layoutManager?.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: length))
            }
        }

        // MARK: Content

        /// Fills the text view when the page or text size changes; other
        /// updates (find state, mostly) leave the text alone.
        func show(_ content: TabContent, textSize: Double) {
            guard let textView, let storage = textView.textStorage else { return }
            let contentChanged = shownContent.map { !Self.isSame($0, content) } ?? true
            guard contentChanged || shownTextSize != textSize else { return }

            let document = contentChanged ? PageDocument(content: content) : (self.document ?? PageDocument(content: content))
            self.document = document
            shownContent = content
            shownTextSize = textSize
            appliedHighlightsVersion = nil

            storage.setAttributedString(Self.render(document, textSize: textSize))
            let font = NSFont.monospacedSystemFont(ofSize: textSize, weight: .regular)
            textView.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]
            textView.configureGutter(document: document, textSize: textSize,
                                     symbols: Self.gutterSymbols(for: document))

            if contentChanged {
                textView.clearHover()
                restoreScrollPosition()
            }
        }

        private static func render(_ document: PageDocument, textSize: Double) -> NSAttributedString {
            let font = NSFont.monospacedSystemFont(ofSize: textSize, weight: .regular)
            var base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
            guard !document.items.isEmpty else {
                return NSAttributedString(string: document.string, attributes: base)
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 2
            base[.paragraphStyle] = paragraph
            let text = NSMutableAttributedString(string: document.string, attributes: base)
            for (index, item) in document.items.enumerated() {
                let range = document.range(ofLine: index)
                guard range.length > 0 else { continue }
                switch item.type {
                case .info:
                    break
                case .error:
                    text.addAttribute(.foregroundColor, value: NSColor.systemRed, range: range)
                default:
                    if let url = URL(string: "\(itemURLScheme):\(index)") {
                        text.addAttribute(.link, value: url, range: range)
                    }
                }
            }
            return text
        }

        /// The icon for each menu line, nil for info lines; empty for text pages.
        private static func gutterSymbols(for document: PageDocument) -> [GutterSymbol?] {
            document.items.map { item in
                switch item.type {
                case .info: return nil
                case .error: return GutterSymbol(name: "exclamationmark.triangle", isError: true)
                default: return GutterSymbol(name: item.type?.symbolName ?? "questionmark.square.dashed",
                                             isError: false)
                }
            }
        }

        /// Pages are value types without identity; a reload brings a new
        /// parse (new item IDs) or a new String.
        private static func isSame(_ a: TabContent, _ b: TabContent) -> Bool {
            switch (a, b) {
            case (.text(let x), .text(let y)): return x == y
            case (.menu(let x), .menu(let y)): return x.count == y.count && x.first?.id == y.first?.id
            default: return false
            }
        }

        // MARK: Links

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let item = item(forLink: link) else { return false }
            // ⌘-click opens menus, text files, and images in a new tab, as
            // in a browser; a plain click on an image opens it over the page.
            let newTab = NSApp.currentEvent?.modifierFlags.contains(.command) == true
                && Self.opensInNewTab(item)
            store?.open(item: item, inNewTab: newTab)
            return true
        }

        /// Items that can be shown in a tab of their own.
        private static func opensInNewTab(_ item: GopherItem) -> Bool {
            item.type == .menu || item.type == .textFile || item.type?.isImage == true
        }

        private func item(forLink link: Any) -> GopherItem? {
            guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)),
                  url.scheme == Self.itemURLScheme,
                  let index = Int(url.absoluteString.dropFirst(Self.itemURLScheme.count + 1)),
                  let items = document?.items, items.indices.contains(index) else { return nil }
            return items[index]
        }

        private func hoverChanged(to line: Int?) {
            guard let line, let items = document?.items, items.indices.contains(line) else {
                store?.linkHoverStatus = nil
                return
            }
            let item = items[line]
            let label = item.type?.label ?? "Item"
            var target = item.address?.urlString ?? ""
            if item.type == .html, item.selector.uppercased().hasPrefix("URL:") {
                target = String(item.selector.dropFirst(4))
            }
            store?.linkHoverStatus = target.isEmpty ? label : "\(label) · \(target)"
        }

        /// The right-click menu for a link line.
        private func linkMenu(forLine line: Int) -> NSMenu? {
            guard let items = document?.items, items.indices.contains(line) else { return nil }
            let item = items[line]
            let menu = NSMenu()
            if Self.opensInNewTab(item) {
                menu.addItem(ClosureMenuItem("Open in New Tab") { [weak self] in
                    self?.store?.open(item: item, inNewTab: true)
                })
            }
            if let address = item.address {
                menu.addItem(ClosureMenuItem("Copy Gopher URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address.urlString, forType: .string)
                })
                menu.addItem(ClosureMenuItem("Download Linked File…") { [weak self] in
                    self?.store?.download(address, suggestedName: item.display)
                })
            }
            return menu.items.isEmpty ? nil : menu
        }

        // MARK: Find

        func applyHighlights(from finder: PageFinder) {
            self.finder = finder
            guard let textView, let layoutManager = textView.layoutManager, let document else { return }
            let current = finder.currentMatch.flatMap { $0.tabID == tab.id ? $0 : nil }
            let darkText = Palette.findMatchUsesDarkText(in: textView.effectiveAppearance)
            guard appliedHighlightsVersion != finder.highlightsVersion || appliedCurrent != current
                    || appliedDarkText != darkText else { return }
            appliedHighlightsVersion = finder.highlightsVersion
            appliedCurrent = current
            appliedDarkText = darkText

            let whole = NSRange(location: 0, length: document.length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
            let ranges = document.highlightRanges(finder.highlights[tab.id], current: current)
            for range in ranges.all {
                layoutManager.addTemporaryAttribute(.backgroundColor, value: Palette.findMatchColor,
                                                    forCharacterRange: range)
                if darkText {
                    layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.black,
                                                        forCharacterRange: range)
                }
            }
            if let range = ranges.current {
                layoutManager.addTemporaryAttributes(
                    [.backgroundColor: NSColor.findHighlightColor,
                     .foregroundColor: NSColor.black], // readable on yellow in dark mode
                    forCharacterRange: range)
            }
        }

        func revealPendingMatch(from finder: PageFinder) {
            guard let match = finder.takeReveal(for: tab.id), let document,
                  let range = document.highlightRanges(finder.highlights[tab.id], current: match).current
            else { return }
            // A page that just appeared hasn't been sized yet.
            DispatchQueue.main.async { [weak self] in self?.scrollToCenter(range) }
        }

        private func scrollToCenter(_ range: NSRange) {
            guard let textView, let scrollView, let layoutManager = textView.layoutManager,
                  let container = textView.textContainer else { return }
            layoutManager.ensureLayout(forCharacterRange: range)
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let origin = textView.textContainerOrigin
            let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: origin.x, dy: origin.y)
            let clip = scrollView.contentView
            let visible = clip.bounds
            var target = NSPoint(x: visible.minX, y: rect.midY - visible.height / 2)
            if rect.minX < visible.minX || rect.maxX > visible.maxX {
                target.x = rect.midX - visible.width / 2
            }
            target = clip.constrainBoundsRect(NSRect(origin: target, size: visible.size)).origin
            clip.scroll(to: target)
            scrollView.reflectScrolledClipView(clip)
            textView.showFindIndicator(for: range)
        }

        // MARK: Scroll memory

        private func observeScroll() {
            guard let clip = scrollView?.contentView else { return }
            clip.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: clip, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.recordScrollPosition() }
            }
        }

        private func recordScrollPosition() {
            guard didRestoreScroll, historyIndex >= 0, let clip = scrollView?.contentView else { return }
            tab.scrollOffsets[historyIndex] = clip.bounds.origin
        }

        /// Back/Forward return to where the page was left; anything else
        /// starts at the top.
        private func restoreScrollPosition() {
            let target = tab.pendingScrollRestore
            tab.pendingScrollRestore = nil
            guard let target, target != .zero else {
                didRestoreScroll = true
                return
            }
            // After the first layout pass sizes the text view.
            DispatchQueue.main.async { [weak self] in
                guard let self, let scrollView = self.scrollView, let textView = self.textView,
                      let layoutManager = textView.layoutManager, let container = textView.textContainer
                else { return }
                let visible = NSRect(origin: target, size: scrollView.contentView.bounds.size)
                layoutManager.ensureLayout(forBoundingRect: visible, in: container)
                scrollView.contentView.scroll(to: target)
                scrollView.reflectScrolledClipView(scrollView.contentView)
                self.didRestoreScroll = true
            }
        }
    }
}

/// A text container whose lines start `gutterWidth` in, leaving a margin
/// for menu icons. Unlike a paragraph indent, the margin isn't part of any
/// line, so selections start at the text instead of bleeding into it.
final class GutterTextContainer: NSTextContainer {
    var gutterWidth: CGFloat = 0

    override var isSimpleRectangularTextContainer: Bool { gutterWidth == 0 }

    override func lineFragmentRect(forProposedRect proposedRect: NSRect,
                                   at characterIndex: Int,
                                   writingDirection baseWritingDirection: NSWritingDirection,
                                   remaining remainingRect: UnsafeMutablePointer<NSRect>?) -> NSRect {
        var rect = super.lineFragmentRect(forProposedRect: proposedRect, at: characterIndex,
                                          writingDirection: baseWritingDirection, remaining: remainingRect)
        guard gutterWidth > 0, rect.width > gutterWidth else { return rect }
        rect.origin.x += gutterWidth
        rect.size.width -= gutterWidth
        return rect
    }
}

/// The SF Symbol drawn in a menu line's gutter.
struct GutterSymbol: Equatable {
    let name: String
    let isError: Bool
}

/// The page text view: copies selections as plain text, draws menu item
/// icons in the left gutter, and tracks the link under the pointer.
final class PageNSTextView: NSTextView {
    var onHoverLine: ((Int?) -> Void)?
    var onAppearanceChange: (() -> Void)?
    var menuForLine: ((Int) -> NSMenu?)?
    private(set) var hoveredLine: Int?
    /// The icon color of the link under the pointer.
    var hoverColor: NSColor = .controlAccentColor {
        didSet {
            imageCache.removeAll()
            needsDisplay = true
        }
    }
    /// Set while Copy as Shown runs, to copy the lines exactly as drawn.
    private var copiesAsShown = false

    private var document: PageDocument?
    private var symbols: [GutterSymbol?] = []
    private var symbolSize: CGFloat = 13
    private var imageCache: [String: NSImage] = [:]
    private var hoverArea: NSTrackingArea?

    /// Set while an image lightbox covers the page. The lightbox blocks
    /// clicks and scrolling, but tracking areas, cursor rects, and the
    /// first responder ignore views drawn on top, so without this the
    /// links beneath would still react to the pointer, and the keyboard
    /// would still scroll and select the dimmed page.
    var isCovered = false {
        didSet {
            guard isCovered != oldValue else { return }
            if isCovered { unmarkHoveredLine() }
            window?.invalidateCursorRects(for: self)
            // Changing the first responder can't happen mid view update.
            DispatchQueue.main.async { [weak self] in self?.updateFocusForCover() }
        }
    }
    /// Keyboard focus was taken from this view when it was covered, and
    /// goes back when it's uncovered.
    private var yieldedFocus = false

    override var acceptsFirstResponder: Bool { !isCovered && super.acceptsFirstResponder }

    private func updateFocusForCover() {
        guard let window else { return }
        if isCovered {
            if window.firstResponder === self {
                yieldedFocus = true
                window.makeFirstResponder(nil)
            }
        } else if yieldedFocus {
            yieldedFocus = false
            // Unless focus has since gone somewhere else, like the address bar.
            if window.firstResponder === window { window.makeFirstResponder(self) }
        }
    }

    override func resetCursorRects() {
        if !isCovered { super.resetCursorRects() }
    }

    override func cursorUpdate(with event: NSEvent) {
        if !isCovered { super.cursorUpdate(with: event) }
    }

    /// Page text carries internal attributes (fonts, item links) that
    /// shouldn't travel to other apps, so only the plain-string type is
    /// offered. It must be one of super's own types: NSTextView can't write
    /// `.string` (public.utf8-plain-text) itself, only its legacy string
    /// type, which other apps still read as plain text.
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.writablePasteboardTypes.filter { $0 == .string || $0.rawValue == "NSStringPboardType" }
    }

    /// On menus, copies paragraphs rather than the hard-wrapped lines
    /// they're sent as (see PageDocument.copyText). Used by Copy, drags,
    /// and Services alike.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let document, !document.items.isEmpty, !copiesAsShown else {
            return super.writeSelection(to: pboard, types: types)
        }
        let ranges = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        guard !ranges.isEmpty else { return false }
        pboard.declareTypes([.string], owner: nil)
        return pboard.setString(ranges.map(document.copyText(for:)).joined(separator: "\n"), forType: .string)
    }

    @objc func copyAsShown(_ sender: Any?) {
        copiesAsShown = true
        defer { copiesAsShown = false }
        copy(sender)
    }

    func configureGutter(document: PageDocument, textSize: Double, symbols: [GutterSymbol?]) {
        self.document = document
        self.symbols = symbols
        if symbolSize != textSize { imageCache.removeAll() }
        symbolSize = textSize
        needsDisplay = true
    }

    // MARK: Gutter icons

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !symbols.isEmpty, let document, let layoutManager, let textContainer else { return }
        let origin = textContainerOrigin
        let containerRect = dirtyRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        guard let first = document.line(at: characters.location),
              let last = document.line(at: NSMaxRange(characters)) else { return }
        for line in first...last {
            guard line < symbols.count, let symbol = symbols[line] else { continue }
            let range = document.range(ofLine: line)
            guard range.length > 0 else { continue }
            let glyph = layoutManager.glyphIndexForCharacter(at: range.location)
            let used = layoutManager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let box = NSRect(x: origin.x, y: origin.y + used.minY,
                             width: PageTextView.Coordinator.gutterWidth - 8, height: used.height)
            guard box.intersects(dirtyRect), let image = image(for: symbol, hovered: line == hoveredLine)
            else { continue }
            let scale = min(box.width / image.size.width, box.height / image.size.height, 1)
            let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                                  width: size.width, height: size.height))
        }
    }

    private func image(for symbol: GutterSymbol, hovered: Bool) -> NSImage? {
        let color: NSColor = symbol.isError ? .systemRed : (hovered ? hoverColor : .secondaryLabelColor)
        let key = "\(symbol.name)|\(symbol.isError)|\(hovered)"
        if let cached = imageCache[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: symbolSize * 0.9, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: symbol.name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        imageCache[key] = image
        return image
    }

    // MARK: Hover

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard !isCovered else { return }
        super.mouseMoved(with: event)
        setHoveredLine(linkLine(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHoveredLine(nil)
    }

    /// Drops the hover underline and icon color without reporting it; the
    /// store clears its own hover label when a lightbox opens.
    private func unmarkHoveredLine() {
        guard let old = hoveredLine else { return }
        if let document {
            layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: document.range(ofLine: old))
        }
        hoveredLine = nil
        needsDisplay = true
    }

    func clearHover() {
        hoveredLine = nil
    }

    private func setHoveredLine(_ line: Int?) {
        guard line != hoveredLine else { return }
        if let old = hoveredLine, let document {
            layoutManager?.removeTemporaryAttribute(.underlineStyle, forCharacterRange: document.range(ofLine: old))
        }
        if let line, let document {
            layoutManager?.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                                                 forCharacterRange: document.range(ofLine: line))
        }
        hoveredLine = line
        needsDisplay = true
        onHoverLine?(line)
    }

    /// The menu line whose link text is under `point`, if any.
    private func linkLine(at point: NSPoint) -> Int? {
        guard let document, let layoutManager, let textContainer, let storage = textStorage,
              storage.length > 0 else { return nil }
        let origin = textContainerOrigin
        let local = NSPoint(x: point.x - origin.x, y: point.y - origin.y)
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer, fractionOfDistanceThroughGlyph: nil)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard glyphRect.contains(local) else { return nil }
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        guard character < storage.length, storage.attribute(.link, at: character, effectiveRange: nil) != nil
        else { return nil }
        return document.line(at: character)
    }

    // MARK: Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let reflows = !(document?.items.isEmpty ?? true)
        guard let line = linkLine(at: point), let menu = menuForLine?(line) else {
            let menu = super.menu(for: event)
            // Offer the raw lines next to Copy, which joins paragraphs.
            if reflows, selectedRange().length > 0, let menu,
               let copyIndex = menu.items.firstIndex(where: { $0.action == #selector(copy(_:)) }) {
                menu.insertItem(withTitle: "Copy as Shown", action: #selector(copyAsShown(_:)),
                                keyEquivalent: "", at: copyIndex + 1)
            }
            return menu
        }
        if selectedRange().length > 0 {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "")
            if reflows {
                menu.addItem(withTitle: "Copy as Shown", action: #selector(copyAsShown(_:)), keyEquivalent: "")
            }
        }
        return menu
    }
}

/// An NSMenuItem that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
}
