import AppKit
import SwiftUI

/// A page's text in a read-only, selectable AppKit text view. TextKit lays
/// out only what's on screen, so very long pages draw (SwiftUI's Text
/// silently fails on huge ones), selection spans the whole page, and find
/// highlights are cheap temporary attributes rather than restyled text.
struct PageTextView: NSViewRepresentable {
    @ObservedObject var tab: BrowserTab
    @EnvironmentObject private var finder: PageFinder
    let content: TabContent
    @AppStorage(ContentTextSize.storageKey) private var textSize = ContentTextSize.default

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab, historyIndex: tab.historyIndex)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView(wraps: false)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.show(content, textSize: textSize)
        coordinator.applyHighlights(from: finder)
        coordinator.revealPendingMatch(from: finder)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stopObservingScroll()
    }

    @MainActor
    final class Coordinator: NSObject {
        private let tab: BrowserTab
        private let historyIndex: Int
        private var scrollView: NSScrollView?
        private var textView: NSTextView?
        private var document: PageDocument?
        private var shownContent: TabContent?
        private var shownTextSize: Double?
        private var appliedHighlightsVersion: Int?
        private var appliedCurrent: FindMatch?
        private var scrollObserver: NSObjectProtocol?
        private var didRestoreScroll = false

        init(tab: BrowserTab, historyIndex: Int) {
            self.tab = tab
            self.historyIndex = historyIndex
        }

        func makeScrollView(wraps: Bool) -> NSScrollView {
            let storage = NSTextStorage()
            // Contiguous layout (the default): non-contiguous layout opens
            // huge pages slightly faster but only estimates the position of
            // text it hasn't laid out, so Back/Forward scroll restoration
            // and scroll-to-match land several lines off.
            let layoutManager = NSLayoutManager()
            storage.addLayoutManager(layoutManager)
            let unbounded = CGFloat.greatestFiniteMagnitude
            let container = NSTextContainer(size: NSSize(width: wraps ? 0 : unbounded, height: unbounded))
            container.widthTracksTextView = wraps
            layoutManager.addTextContainer(container)

            let textView = PlainCopyTextView(frame: .zero, textContainer: container)
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
            textView.textContainerInset = NSSize(width: 16, height: 16)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = !wraps
            textView.autoresizingMask = wraps ? [.width] : []
            textView.minSize = .zero
            textView.maxSize = NSSize(width: unbounded, height: unbounded)

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

        // MARK: Content

        /// Fills the text view when the page or text size changes; other
        /// updates (find state, mostly) leave the text alone.
        func show(_ content: TabContent, textSize: Double) {
            guard let textView, let storage = textView.textStorage else { return }
            let contentChanged = shownContent.map { !Self.isSame($0, content) } ?? true
            guard contentChanged || shownTextSize != textSize else { return }

            if contentChanged {
                let document = PageDocument(content: content)
                self.document = document
                storage.setAttributedString(NSAttributedString(string: document.string))
                appliedHighlightsVersion = nil
            }
            shownContent = content
            shownTextSize = textSize

            let font = NSFont.monospacedSystemFont(ofSize: textSize, weight: .regular)
            storage.setAttributes([.font: font, .foregroundColor: NSColor.textColor],
                                  range: NSRange(location: 0, length: storage.length))
            textView.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]

            if contentChanged { restoreScrollPosition() }
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

        // MARK: Find

        func applyHighlights(from finder: PageFinder) {
            guard let textView, let layoutManager = textView.layoutManager, let document else { return }
            let current = finder.currentMatch.flatMap { $0.tabID == tab.id ? $0 : nil }
            guard appliedHighlightsVersion != finder.highlightsVersion || appliedCurrent != current else { return }
            appliedHighlightsVersion = finder.highlightsVersion
            appliedCurrent = current

            let whole = NSRange(location: 0, length: document.length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
            let ranges = document.highlightRanges(finder.highlights[tab.id], current: current)
            for range in ranges.all {
                layoutManager.addTemporaryAttribute(.backgroundColor, value: Palette.mossWashColor,
                                                    forCharacterRange: range)
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

        func stopObservingScroll() {
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
            scrollObserver = nil
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

/// Copies selections as plain text: page text carries internal attributes
/// (fonts, item links) that shouldn't travel to other apps.
final class PlainCopyTextView: NSTextView {
    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }
}
