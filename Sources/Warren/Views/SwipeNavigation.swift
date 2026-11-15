import AppKit
import QuartzCore
import SwiftUI

/// A picture of a page as it looked when the user left it, at its scroll
/// position. Used as the page underneath during a swipe.
struct PageSnapshot {
    let image: CGImage
    /// The page area's size in points when taken; a snapshot taken at
    /// another size (window resized since) isn't used.
    let size: CGSize
    let appearance: NSAppearance.Name?
    let textSize: Double
    let theme: String
}

/// Swipe between pages (issue #7) for one browser window: decides when a
/// sideways two-finger scroll should go Back or Forward instead of
/// scrolling, and drives the slide over the page area, Safari style. The
/// page follows the fingers over a picture of the page it's going to, or
/// over the pickaxe backdrop when there's nowhere further to go.
///
/// Scroll events reach it two ways: a window-wide monitor sees every
/// gesture as it starts, and `SwipeResponder` receives the gestures that
/// scroll views pass up once their content is at the edge.
@MainActor
final class SwipeNavigator {
    private weak var store: BrowserStore?
    private weak var overlay: SwipeOverlayView?
    private var monitor: Any?

    /// At most this many snapshots per tab, the ones nearest the current
    /// page; a full-window Retina picture is several megabytes.
    static let maxSnapshotsPerTab = 8

    private enum Gesture {
        case idle
        /// Fingers down, not yet sure whether this is a swipe.
        case undecided(dx: CGFloat, dy: CGFloat)
        /// Not a swipe; let the rest of the gesture scroll as usual.
        case passThrough
        case swiping
        /// Already acted on without a slide (closing an image); the rest
        /// of the gesture is ignored.
        case swallowing
    }
    private var gesture = Gesture.idle

    /// Receives sideways gestures that scroll views pass up because their
    /// content is already at that edge (see `SwipeResponder`).
    private lazy var responder = SwipeResponder(navigator: self)

    /// The last event looked at and what was decided, since an event can
    /// reach both the monitor and the responder.
    private var lastEvent: (time: TimeInterval, phase: UInt, consumed: Bool)?

    init(store: BrowserStore) {
        self.store = store
    }

    // MARK: - Overlay, monitor and responder

    func attach(_ view: SwipeOverlayView) {
        overlay = view
        view.onWindowChange = { [weak self] in self?.insertResponder() }
        insertResponder()
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { self?.consumes(event) ?? false }
            return consumed ? nil : event
        }
    }

    func detach(_ view: SwipeOverlayView) {
        guard overlay === view else { return }
        removeResponder(from: view.window)
        overlay = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        gesture = .idle
    }

    /// Puts the swipe responder in the window's responder chain just
    /// before the window itself, so scroll views anywhere in the page can
    /// pass it a swipe. The content view is followed by its hosting view
    /// controller, so the responder goes after whatever comes last.
    private func insertResponder() {
        guard let window = overlay?.window, let contentView = window.contentView else { return }
        var last: NSResponder = contentView
        var steps = 0
        while let next = last.nextResponder, next !== window, steps < 20 {
            if next === responder { return } // already in place
            last = next
            steps += 1
        }
        guard last.nextResponder === window else { return }
        responder.nextResponder = window
        last.nextResponder = responder
    }

    private func removeResponder(from window: NSWindow?) {
        guard let contentView = window?.contentView else { return }
        var current: NSResponder = contentView
        var steps = 0
        while let next = current.nextResponder, steps < 20 {
            if next === responder {
                current.nextResponder = responder.nextResponder
                return
            }
            current = next
            steps += 1
        }
    }

    // MARK: - Snapshots

    /// Takes a picture of the page the selected tab is showing and files it
    /// under the page's history slot. Call just before the page changes.
    func capturePage(of tab: BrowserTab) {
        guard tab === store?.selectedTab, let slot = pageSlot(of: tab),
              let snapshot = takeSnapshot() else { return }
        tab.snapshots[slot] = snapshot
        trimSnapshots(of: tab)
    }

    /// The history slot of what the tab is showing: -1 for the Home page
    /// it started on. Nil when what's showing isn't a picture of a history
    /// stop: Go → Home over a page, the previous page while a new one
    /// loads, or an image covering the page.
    private func pageSlot(of tab: BrowserTab) -> Int? {
        guard !tab.isLoading, tab.lightbox == nil else { return nil }
        if tab.historyIndex == -1 { return tab.startedAtHome ? -1 : nil }
        guard tab.history.indices.contains(tab.historyIndex), !tab.isShowingHome else { return nil }
        return tab.historyIndex
    }

    private func trimSnapshots(of tab: BrowserTab) {
        guard tab.snapshots.count > Self.maxSnapshotsPerTab else { return }
        let keep = tab.snapshots.keys
            .sorted { abs($0 - tab.historyIndex) < abs($1 - tab.historyIndex) }
            .prefix(Self.maxSnapshotsPerTab)
        tab.snapshots = tab.snapshots.filter { keep.contains($0.key) }
    }

    /// The page area as it's drawn now, overlay excluded.
    private func takeSnapshot() -> PageSnapshot? {
        guard let overlay, let contentView = overlay.window?.contentView,
              overlay.bounds.width > 0, overlay.bounds.height > 0 else { return nil }
        let wasHidden = overlay.isHidden
        overlay.isHidden = true
        defer { overlay.isHidden = wasHidden }

        let rect = overlay.convert(overlay.bounds, to: contentView)
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        contentView.cacheDisplay(in: rect, to: rep)
        guard let image = rep.cgImage else { return nil }
        return PageSnapshot(image: image, size: overlay.bounds.size,
                            appearance: overlay.effectiveAppearance.name,
                            textSize: Self.currentTextSize, theme: Self.currentTheme)
    }

    /// A snapshot that still matches how the page would draw now.
    private func usableSnapshot(_ snapshot: PageSnapshot?) -> PageSnapshot? {
        guard let snapshot, let overlay,
              abs(snapshot.size.width - overlay.bounds.width) < 1,
              abs(snapshot.size.height - overlay.bounds.height) < 1,
              snapshot.appearance == overlay.effectiveAppearance.name,
              snapshot.textSize == Self.currentTextSize,
              snapshot.theme == Self.currentTheme else { return nil }
        return snapshot
    }

    private static var currentTextSize: Double {
        let size = UserDefaults.standard.double(forKey: ContentTextSize.storageKey)
        return size == 0 ? ContentTextSize.default : size
    }

    private static var currentTheme: String {
        UserDefaults.standard.string(forKey: Theme.storageKey) ?? Theme.monochrome.rawValue
    }

    // MARK: - Gesture

    /// Whether a scroll event belongs to a swipe, and so shouldn't scroll
    /// the page.
    ///
    /// `forwarded` events come through the responder chain from a scroll
    /// view that has already checked it's at the edge; the rest come from
    /// the window-wide monitor.
    fileprivate func consumes(_ event: NSEvent, forwarded: Bool = false) -> Bool {
        guard let overlay, event.window === overlay.window else { return false }
        let key = (event.timestamp, event.phase.rawValue)
        if let lastEvent, lastEvent.time == key.0, lastEvent.phase == key.1 {
            return lastEvent.consumed
        }
        let consumed = decide(event, forwarded: forwarded)
        lastEvent = (key.0, key.1, consumed)
        return consumed
    }

    private func decide(_ event: NSEvent, forwarded: Bool) -> Bool {
        // AppKit still routes the swipe's own scroll events here while it
        // tracks them; they mustn't scroll the page.
        if case .swiping = gesture { return true }
        if case .swallowing = gesture {
            if event.phase == .ended || event.phase == .cancelled { gesture = .idle }
            return true
        }
        // Momentum after the fingers lift, and mouse wheels, never swipe.
        guard event.momentumPhase.isEmpty, !event.phase.isEmpty else { return false }

        switch event.phase {
        case .began, .mayBegin:
            gesture = .undecided(dx: 0, dy: 0)
            return false
        case .changed:
            // A scroll view may start passing a gesture up partway in.
            if forwarded, case .idle = gesture { gesture = .undecided(dx: 0, dy: 0) }
            guard case .undecided(var dx, var dy) = gesture else { return false }
            dx += event.scrollingDeltaX
            dy += event.scrollingDeltaY
            // Wait for enough movement to tell the direction.
            guard hypot(dx, dy) >= 6 else {
                gesture = .undecided(dx: dx, dy: dy)
                return false
            }
            guard abs(dx) > abs(dy) * 1.5 else {
                gesture = .passThrough
                return false
            }
            gesture = beginSwipe(with: event, dx: dx, checkEdge: !forwarded)
            if case .passThrough = gesture { return false }
            return true
        default:
            gesture = .idle
            return false
        }
    }

    /// Starts a swipe from a sideways gesture and returns what the rest of
    /// the gesture is: a tracked swipe, ignored (when it closed an image),
    /// or `.passThrough` to let it scroll the page instead.
    private func beginSwipe(with event: NSEvent, dx: CGFloat, checkEdge: Bool) -> Gesture {
        // System Settings → Trackpad → More Gestures → Swipe between pages.
        guard NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              let store, let tab = store.selectedTab, let overlay,
              !tab.isLoading else { return .passThrough }

        // Content deltas follow the scroll-direction setting; work out
        // which way the fingers actually moved. Fingers right = Back.
        let towardBack = (dx > 0) == event.isDirectionInvertedFromDevice

        // An image opened from the page: Back closes it, like the Back
        // button (Forward slides to the next page as usual).
        if towardBack, tab.lightbox != nil {
            store.goBack()
            return .swallowing
        }

        // Content that scrolls sideways scrolls until it reaches the edge.
        if checkEdge, let scrollView = scrollView(under: event),
           !isAtEdge(scrollView, towardBack: towardBack) {
            return .passThrough
        }

        // gestureAmount has the sign of the deltas; turn it into "toward
        // Back" (positive) and "toward Forward" (negative).
        let dxSign: CGFloat = dx > 0 ? 1 : -1
        let backSign: CGFloat = towardBack ? dxSign : -dxSign
        let canBack = tab.canGoBack
        let canForward = tab.canGoForward
        // Past the last page in a direction the page only rubber-bands.
        let backLimit: CGFloat = canBack ? 1 : 0
        let forwardLimit: CGFloat = canForward ? 1 : 0
        let minAmount = backSign > 0 ? -forwardLimit : -backLimit
        let maxAmount = backSign > 0 ? backLimit : forwardLimit

        guard let current = takeSnapshot() else { return .passThrough }
        // Leaving this page either way, so keep the fresh picture.
        if let slot = pageSlot(of: tab) { tab.snapshots[slot] = current }
        let backPicture = canBack ? usableSnapshot(tab.snapshots[tab.historyIndex - 1]) : nil
        let forwardPicture = canForward ? usableSnapshot(tab.snapshots[tab.historyIndex + 1]) : nil

        overlay.begin(current: current.image,
                      back: canBack ? .page(backPicture?.image) : .endOfHistory,
                      forward: canForward ? .page(forwardPicture?.image) : .endOfHistory)

        var committed: Bool?
        let tabID = tab.id
        // No clamping: past a limit of 0 the amount rubber-bands.
        event.trackSwipeEvent(options: [.lockDirection],
                              dampenAmountThresholdMin: minAmount,
                              max: maxAmount) { [weak self] amount, phase, isComplete, stop in
            MainActor.assumeIsolated {
                guard let self, let overlay = self.overlay else {
                    stop.pointee = true
                    return
                }
                // A tab switch mid-swipe abandons it.
                if self.store?.selectedTabID != tabID {
                    stop.pointee = true
                    overlay.end()
                    self.gesture = .idle
                    return
                }
                let progress = amount * backSign
                overlay.show(progress: progress)
                if phase == .ended { committed = true }
                if phase == .cancelled { committed = false }
                if isComplete {
                    self.gesture = .idle
                    self.finish(committed: committed == true, progress: progress)
                }
            }
        }
        return .swiping
    }

    /// A three-finger swipe, when that's the Swipe between pages setting:
    /// AppKit sends a single swipe event instead of scrolls, so it goes
    /// straight to the page without a slide.
    fileprivate func handleSwipe(_ event: NSEvent) -> Bool {
        guard let store, let overlay, event.window === overlay.window,
              event.deltaX != 0 else { return false }
        // -1 is a swipe to the right: Back.
        if event.deltaX < 0 { store.goBack() } else { store.goForward() }
        return true
    }

    private func finish(committed: Bool, progress: CGFloat) {
        guard let store, let overlay else { return }
        guard committed, abs(progress) > 0.5 else {
            overlay.end()
            return
        }
        if progress > 0 { store.goBack() } else { store.goForward() }
        // Keep the picture up until the real page has drawn and restored
        // its scroll position (ScrollMemory waits a runloop turn).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak overlay] in
            overlay?.end(fade: true)
        }
    }

    /// The scroll view under the pointer, if any.
    private func scrollView(under event: NSEvent) -> NSScrollView? {
        guard let contentView = event.window?.contentView,
              let frameView = contentView.superview else { return nil }
        let point = frameView.convert(event.locationInWindow, from: nil)
        guard let hit = contentView.hitTest(point) else { return nil }
        return (hit as? NSScrollView) ?? hit.enclosingScrollView
    }

    /// Whether sideways content is already scrolled to the edge the swipe
    /// moves away from. Content that doesn't scroll sideways always is.
    private func isAtEdge(_ scrollView: NSScrollView, towardBack: Bool) -> Bool {
        guard let document = scrollView.documentView else { return true }
        let visible = scrollView.contentView.bounds
        let content = document.frame
        let slack: CGFloat = 1
        guard content.width > visible.width + slack else { return true }
        return towardBack
            ? visible.minX <= content.minX + slack
            : visible.maxX >= content.maxX - slack
    }
}

// MARK: - Responder

/// Sits in the window's responder chain and asks scroll views to pass up
/// sideways gestures that start with their content already at that edge.
/// Scroll views take over a gesture once it starts, so the window-wide
/// monitor never sees the rest of it; this is how the swipe reaches us.
final class SwipeResponder: NSResponder {
    private weak var navigator: SwipeNavigator?

    init(navigator: SwipeNavigator) {
        self.navigator = navigator
        super.init()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        axis == .horizontal
    }

    override func scrollWheel(with event: NSEvent) {
        if navigator?.consumes(event, forwarded: true) != true {
            super.scrollWheel(with: event)
        }
    }

    override func swipe(with event: NSEvent) {
        if navigator?.handleSwipe(event) != true {
            super.swipe(with: event)
        }
    }
}

// MARK: - Overlay

/// Draws the slide over the page area. Hidden, and transparent to the
/// mouse, except while a swipe is in progress.
final class SwipeOverlayView: NSView {
    enum Destination {
        /// A page; nil when there's no up-to-date picture of it.
        case page(CGImage?)
        /// Nothing further this way.
        case endOfHistory
    }

    private let root = CALayer()
    private let currentLayer = CALayer()
    private let otherLayer = CALayer()
    private let dimLayer = CALayer()
    private var back = Destination.endOfHistory
    private var forward = Destination.endOfHistory
    private var progress: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = root
        wantsLayer = true
        root.masksToBounds = true
        for sublayer in [otherLayer, dimLayer, currentLayer] {
            sublayer.contentsGravity = .resize
            root.addSublayer(sublayer)
        }
        currentLayer.shadowOpacity = 0.25
        currentLayer.shadowRadius = 10
        currentLayer.shadowOffset = .zero
        dimLayer.backgroundColor = NSColor.black.cgColor
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    var onWindowChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }

    func begin(current: CGImage, back: Destination, forward: Destination) {
        self.back = back
        self.forward = forward
        withoutAnimation {
            root.opacity = 1
            currentLayer.contents = current
        }
        isHidden = false
        show(progress: 0)
    }

    /// Positive progress moves toward Back, negative toward Forward; ±1 is
    /// all the way.
    func show(progress: CGFloat) {
        self.progress = progress
        layoutLayers()
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    private func layoutLayers() {
        let width = bounds.width
        let p = progress
        withoutAnimation {
            let scale = window?.backingScaleFactor ?? 2
            for sublayer in [currentLayer, otherLayer] { sublayer.contentsScale = scale }
            if p >= 0 {
                // Back: this page slides right, uncovering the one before.
                fill(otherLayer, with: back)
                if case .endOfHistory = back {
                    // The backdrop stays put and undimmed.
                    otherLayer.frame = bounds
                    dimLayer.opacity = 0
                } else {
                    otherLayer.frame = bounds.offsetBy(dx: -width * 0.25 * (1 - p), dy: 0)
                    dimLayer.opacity = Float(0.12 * (1 - p))
                }
                currentLayer.frame = bounds.offsetBy(dx: width * p, dy: 0)
                currentLayer.zPosition = 1
                otherLayer.zPosition = 0
            } else {
                // Forward: the next page slides in from the right, over this one.
                let q = -p
                if case .page(let image) = forward {
                    fill(otherLayer, with: .page(image))
                    otherLayer.frame = bounds.offsetBy(dx: width * (1 - q), dy: 0)
                    otherLayer.zPosition = 1
                    currentLayer.frame = bounds.offsetBy(dx: -width * 0.25 * q, dy: 0)
                    currentLayer.zPosition = 0
                    dimLayer.opacity = Float(0.12 * q)
                } else {
                    // Nothing ahead: this page pulls left, showing the backdrop.
                    fill(otherLayer, with: .endOfHistory)
                    otherLayer.frame = bounds
                    otherLayer.zPosition = 0
                    currentLayer.frame = bounds.offsetBy(dx: -width * q, dy: 0)
                    currentLayer.zPosition = 1
                    dimLayer.opacity = 0
                }
            }
            dimLayer.frame = bounds
            dimLayer.zPosition = 0.5
            currentLayer.shadowPath = CGPath(rect: currentLayer.bounds, transform: nil)
        }
    }

    private func fill(_ layer: CALayer, with destination: Destination) {
        switch destination {
        case .page(let image?):
            layer.contents = image
            layer.backgroundColor = nil
        case .page(nil):
            // No picture: a plain page until the real one draws.
            layer.contents = nil
            layer.backgroundColor = NSColor.textBackgroundColor.cgColor(for: self)
        case .endOfHistory:
            let theme = UserDefaults.standard.string(forKey: Theme.storageKey)
                .flatMap(Theme.init(rawValue:)) ?? .monochrome
            let dark = Palette.isDark(effectiveAppearance)
            layer.contents = PickaxeBackdrop.image(size: bounds.size,
                                                   scale: window?.backingScaleFactor ?? 2,
                                                   theme: theme, dark: dark)
            layer.backgroundColor = PickaxeBackdrop.colors(for: theme, dark: dark).background.cgColor
        }
    }

    func end(fade: Bool = false) {
        guard fade else {
            isHidden = true
            clear()
            return
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setCompletionBlock { [weak self] in
            self?.isHidden = true
            self?.clear()
        }
        root.opacity = 0
        CATransaction.commit()
    }

    private func clear() {
        withoutAnimation {
            currentLayer.contents = nil
            otherLayer.contents = nil
            root.opacity = 1
        }
        progress = 0
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}

private extension NSColor {
    func cgColor(for view: NSView) -> CGColor {
        var color = cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { color = self.cgColor }
        return color
    }
}

/// Puts the swipe overlay over the page area and hands it to the window's
/// navigator.
struct SwipeOverlay: NSViewRepresentable {
    let navigator: SwipeNavigator

    func makeCoordinator() -> SwipeNavigator { navigator }

    func makeNSView(context: Context) -> SwipeOverlayView {
        let view = SwipeOverlayView(frame: .zero)
        navigator.attach(view)
        return view
    }

    func updateNSView(_ nsView: SwipeOverlayView, context: Context) {
        navigator.attach(nsView)
    }

    static func dismantleNSView(_ nsView: SwipeOverlayView, coordinator: SwipeNavigator) {
        coordinator.detach(nsView)
    }
}
