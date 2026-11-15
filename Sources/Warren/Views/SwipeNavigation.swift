import AppKit
import Combine
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
    let theme: Theme
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

    /// At most this many snapshots for the selected tab, the ones nearest
    /// the current page; a full-window Retina picture is tens of
    /// megabytes. Tabs in the background keep only the pages either side
    /// of theirs, and closed tabs none.
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

    /// Numbers the swipe being tracked, so callbacks from one that was
    /// abandoned are ignored.
    private var swipeID = 0
    /// When AppKit last reported on the tracked swipe.
    private var lastSwipeUpdate: TimeInterval = 0

    /// Receives sideways gestures that scroll views pass up because their
    /// content is already at that edge (see `SwipeResponder`).
    private let responder = SwipeResponder()
    /// The responder ours is spliced in after. `nextResponder` isn't
    /// retained, so ours must come back out before it's freed.
    private weak var responderHost: NSResponder?

    /// After a swipe, what the slide is waiting on before it uncovers the
    /// real page.
    private var pageWaits: Set<AnyCancellable> = []

    /// The last event looked at and what was decided, since an event can
    /// reach both the monitor and the responder.
    private var lastEvent: (time: TimeInterval, phase: UInt, consumed: Bool)?

    init(store: BrowserStore) {
        self.store = store
        responder.navigator = self
    }

    deinit {
        let responder = responder
        let host = responderHost
        nonisolated(unsafe) let monitor = monitor
        // A window's store, and this with it, is released on the main thread.
        MainActor.assumeIsolated {
            if let host, host.nextResponder === responder {
                host.nextResponder = responder.nextResponder
            }
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    // MARK: - Overlay, monitor and responder

    func attach(_ view: SwipeOverlayView) {
        overlay = view
        view.onWindowChange = { [weak self] in self?.insertResponder() }
        insertResponder()
        guard monitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        monitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return event.type == .scrollWheel ? self.consumes(event) : self.blocksClick(event)
            }
            return consumed ? nil : event
        }
    }

    func detach(_ view: SwipeOverlayView) {
        guard overlay === view else { return }
        abandonSwipe()
        removeResponder()
        overlay = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// While the slide is up, a click on it mustn't reach the page hidden
    /// underneath.
    private func blocksClick(_ event: NSEvent) -> Bool {
        guard let overlay, !overlay.isHidden, event.window === overlay.window else { return false }
        return isOverPage(event)
    }

    private func isOverPage(_ event: NSEvent) -> Bool {
        guard let overlay else { return false }
        return overlay.bounds.contains(overlay.convert(event.locationInWindow, from: nil))
    }

    /// Puts the swipe responder in the window's responder chain just
    /// before the window itself, so scroll views anywhere in the page can
    /// pass it a swipe. The content view is followed by its hosting view
    /// controller, so the responder goes after whatever comes last.
    private func insertResponder() {
        guard let window = overlay?.window, let contentView = window.contentView else {
            // The overlay left its window (the window is closing).
            removeResponder()
            return
        }
        var last: NSResponder = contentView
        var steps = 0
        while let next = last.nextResponder, next !== window, steps < 20 {
            if next === responder { return } // already in place
            last = next
            steps += 1
        }
        guard last.nextResponder === window else { return }
        removeResponder() // from a window the overlay was in before
        responder.nextResponder = window
        last.nextResponder = responder
        responderHost = last
    }

    private func removeResponder() {
        if let host = responderHost, host.nextResponder === responder {
            host.nextResponder = responder.nextResponder
        }
        responderHost = nil
        responder.nextResponder = nil
    }

    // MARK: - Snapshots

    /// Takes a picture of the page the selected tab is showing and files it
    /// under the page's history slot. Call just before the page changes.
    func capturePage(of tab: BrowserTab) {
        // Pictures are only for the slide; skip the work when the system
        // setting for it is off (or set to three fingers, which doesn't
        // slide).
        guard NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              tab === store?.selectedTab, let slot = pageSlot(of: tab),
              let snapshot = takeSnapshot() else { return }
        tab.snapshots[slot] = snapshot
        trimSnapshots(of: tab)
    }

    /// A tab going into the background keeps only the pictures a first
    /// swipe would need when it comes back.
    func trimForBackground(_ tab: BrowserTab) {
        tab.snapshots = tab.snapshots.filter { abs($0.key - tab.historyIndex) == 1 }
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
        // Pictures that no longer match the window can't be shown again.
        tab.snapshots = tab.snapshots.filter { usableSnapshot($0.value) != nil }
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
        // Passing things like the link-hover label aren't part of the page.
        let excluded = PagePictureExcludedView.hideAll(in: overlay.window)
        defer {
            overlay.isHidden = wasHidden
            for view in excluded { view.isHidden = false }
        }

        let rect = overlay.convert(overlay.bounds, to: contentView)
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        contentView.cacheDisplay(in: rect, to: rep)
        guard let image = rep.cgImage else { return nil }
        return PageSnapshot(image: image, size: overlay.bounds.size,
                            appearance: overlay.effectiveAppearance.name,
                            textSize: Self.currentTextSize, theme: .current)
    }

    /// A snapshot that still matches how the page would draw now.
    private func usableSnapshot(_ snapshot: PageSnapshot?) -> PageSnapshot? {
        guard let snapshot, let overlay,
              abs(snapshot.size.width - overlay.bounds.width) < 1,
              abs(snapshot.size.height - overlay.bounds.height) < 1,
              snapshot.appearance == overlay.effectiveAppearance.name,
              snapshot.textSize == Self.currentTextSize,
              snapshot.theme == .current else { return nil }
        return snapshot
    }

    private static var currentTextSize: Double {
        let size = UserDefaults.standard.double(forKey: ContentTextSize.storageKey)
        return size == 0 ? ContentTextSize.default : size
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
        if case .swiping = gesture {
            if event.phase == .ended || event.phase == .cancelled { expectSwipeToFinish() }
            // A new gesture long after the tracker went quiet: it never
            // finished, so don't let it hold the window's scrolling.
            guard event.phase == .began, CACurrentMediaTime() - lastSwipeUpdate > 1.5 else { return true }
            abandonSwipe()
        }
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
        case .stationary:
            // Fingers resting; the gesture is still going.
            return false
        default:
            gesture = .idle
            return false
        }
    }

    /// The fingers have lifted, so AppKit should finish the swipe's
    /// animation within moments. If it never reports back, take the slide
    /// down rather than leave a picture over the page.
    private func expectSwipeToFinish() {
        let id = swipeID
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.swipeID == id, case .swiping = self.gesture else { return }
                self.abandonSwipe()
            }
        }
    }

    /// Drops the swipe in progress, if any, and anything it left on screen.
    private func abandonSwipe() {
        swipeID += 1
        pageWaits.removeAll()
        gesture = .idle
        overlay?.end()
    }

    /// Starts a swipe from a sideways gesture and returns what the rest of
    /// the gesture is: a tracked swipe, ignored (when it closed an image),
    /// or `.passThrough` to let it scroll the page instead.
    private func beginSwipe(with event: NSEvent, dx: CGFloat, checkEdge: Bool) -> Gesture {
        // System Settings → Trackpad → More Gestures → Swipe between pages.
        guard NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              let store, let tab = store.selectedTab, let overlay,
              !tab.isLoading,
              // Only over the page: the tab bar, toolbar and find bar keep
              // their own sideways scrolling.
              isOverPage(event) else { return .passThrough }

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
        swipeID += 1
        let id = swipeID
        lastSwipeUpdate = CACurrentMediaTime()
        pageWaits.removeAll() // a slide still waiting on the last swipe's page
        // No clamping: past a limit of 0 the amount rubber-bands.
        event.trackSwipeEvent(options: [.lockDirection],
                              dampenAmountThresholdMin: minAmount,
                              max: maxAmount) { [weak self] amount, phase, isComplete, stop in
            MainActor.assumeIsolated {
                guard let self, self.swipeID == id else {
                    stop.pointee = true // abandoned
                    return
                }
                // A tab switch mid-swipe abandons it.
                guard let overlay = self.overlay, self.store?.selectedTabID == tabID else {
                    stop.pointee = true
                    self.abandonSwipe()
                    return
                }
                self.lastSwipeUpdate = CACurrentMediaTime()
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
        holdSlideUntilPageShows()
    }

    /// Keeps the slide's last frame up until the real page is showing. A
    /// page that isn't cached (a reopened session's) has to load first,
    /// and until it does the page underneath is still the one swiped away.
    private func holdSlideUntilPageShows() {
        pageWaits.removeAll()
        guard let store, let tab = store.selectedTab, tab.isLoading else {
            uncoverPage(fade: true)
            return
        }
        tab.$isLoading.dropFirst().filter { !$0 }.first()
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.uncoverPage(fade: true) } }
            .store(in: &pageWaits)
        // The slide belongs to this tab's page, not the one switched to.
        store.$selectedTabID.dropFirst().first()
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.uncoverPage(fade: false) } }
            .store(in: &pageWaits)
    }

    private func uncoverPage(fade: Bool) {
        pageWaits.removeAll()
        guard fade, let overlay else {
            overlay?.end()
            return
        }
        // Give the page a moment to draw and restore its scroll position
        // (ScrollMemory waits a runloop turn).
        let slide = overlay.slide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak overlay] in
            guard let overlay, overlay.slide == slide else { return } // a new swipe began
            overlay.end(fade: true)
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
    weak var navigator: SwipeNavigator?

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
    /// The theme and mode of the end-of-history backdrop for this slide.
    private var backdrop: (theme: Theme, dark: Bool) = (.monochrome, false)
    /// Counts slides, so a fade-out left over from the last one can't
    /// take down the next.
    private(set) var slide = 0

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
        slide += 1
        backdrop = (.current, Palette.isDark(effectiveAppearance))
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
            // Drawn once and reused until the size, theme or mode changes.
            layer.contents = PickaxeBackdrop.image(size: bounds.size,
                                                   scale: window?.backingScaleFactor ?? 2,
                                                   theme: backdrop.theme, dark: backdrop.dark)
            layer.backgroundColor = nil
        }
    }

    func end(fade: Bool = false) {
        guard fade else {
            isHidden = true
            clear()
            return
        }
        let slide = slide
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.slide == slide else { return } // a new swipe began
            self.isHidden = true
            self.clear()
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

// MARK: - Left out of page pictures

/// Hosts a view in its own AppKit view so it can be hidden, at once, while
/// a page picture is taken. For things drawn over the page that aren't
/// part of it, like the link-hover label: a picture that included it would
/// show that label again when the page slides back in.
struct ExcludedFromPagePictures<Content: View>: NSViewRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> PagePictureExcludedView {
        PagePictureExcludedView(rootView: AnyView(content))
    }

    func updateNSView(_ nsView: PagePictureExcludedView, context: Context) {
        nsView.rootView = AnyView(content)
    }

    /// The content's own size, narrowed to the space on offer.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PagePictureExcludedView,
                      context: Context) -> CGSize? {
        let ideal = nsView.fittingSize
        return CGSize(width: min(ideal.width, proposal.width ?? ideal.width), height: ideal.height)
    }
}

final class PagePictureExcludedView: NSHostingView<AnyView> {
    private static let all = NSHashTable<PagePictureExcludedView>.weakObjects()

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        Self.all.add(self)
    }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Hides every such view showing in a window and returns them, to be
    /// shown again once the picture is taken.
    static func hideAll(in window: NSWindow?) -> [NSView] {
        guard let window else { return [] }
        let showing = all.allObjects.filter { $0.window === window && !$0.isHidden }
        for view in showing { view.isHidden = true }
        return showing
    }
}
