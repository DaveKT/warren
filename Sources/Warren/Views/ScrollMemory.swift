import AppKit
import SwiftUI

/// Invisible helper placed inside a page's ScrollView content. It finds
/// the enclosing NSScrollView to (a) continuously record the scroll
/// offset into the tab's history slot for this page, and (b) jump to a
/// previously recorded offset when the page is shown via Back/Forward.
struct ScrollMemory: NSViewRepresentable {
    let tab: BrowserTab
    let index: Int

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.configure(tab: tab, index: index)
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.configure(tab: tab, index: index)
    }

    final class TrackerView: NSView {
        private weak var tab: BrowserTab?
        private var index = -1
        private var observer: NSObjectProtocol?
        private var didRestore = false

        func configure(tab: BrowserTab, index: Int) {
            self.tab = tab
            self.index = index
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, observer == nil else { return }
            // The scroll view exists only after this view lands in the
            // hierarchy; defer one runloop turn for layout to settle.
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard observer == nil, let scrollView = enclosingScrollView else { return }

            if !didRestore {
                didRestore = true
                if let target = tab?.pendingScrollRestore {
                    tab?.pendingScrollRestore = nil
                    if target != .zero {
                        scrollView.contentView.scroll(to: target)
                        scrollView.reflectScrolledClipView(scrollView.contentView)
                    }
                }
            }

            scrollView.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                // Delivered on the main queue (see `queue:` above).
                MainActor.assumeIsolated {
                    guard let self, let tab = self.tab, self.index >= 0,
                          let origin = scrollView?.contentView.bounds.origin else { return }
                    tab.scrollOffsets[self.index] = origin
                }
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
