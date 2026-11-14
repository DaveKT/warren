import AppKit
import SwiftUI

/// An image opened from a link on the page, shown over the tab's page,
/// which it dims. It isn't modal: the tab bar and other tabs stay usable,
/// and each tab keeps its own image as the user switches between them.
/// Esc, Back, ⌘W, the close button, or a click outside the image closes it.
struct LightboxView: View {
    @EnvironmentObject private var store: BrowserStore
    @Environment(\.colorScheme) private var colorScheme
    let tab: BrowserTab
    let lightbox: Lightbox

    /// Room around the card, and around the image inside it.
    private static let margin: CGFloat = 32
    private static let imagePadding: CGFloat = 16
    /// Enough for the header's title and buttons.
    private static let minCardWidth: CGFloat = 340
    private static let headerHeight: CGFloat = 52

    var body: some View {
        ZStack {
            Color.black.opacity(colorScheme == .dark ? 0.55 : 0.4)
                .contentShape(Rectangle())
                .onTapGesture { store.closeImage(in: tab) }

            GeometryReader { geometry in
                card(fitting: geometry.size)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .padding(Self.margin)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image: \(title)")
    }

    /// The link's text, with the runs of spaces that menus use to line up
    /// columns (sizes, dates) collapsed so the header shows more of it.
    private var title: String {
        let words = lightbox.title.split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? lightbox.address.displayString : words.joined(separator: " ")
    }

    private func card(fitting space: CGSize) -> some View {
        let imageSpace = CGSize(width: space.width - 2 * Self.imagePadding,
                                height: space.height - Self.headerHeight - 2 * Self.imagePadding)
        var width = Self.minCardWidth
        if case .loaded(let image) = lightbox.state {
            width = max(width, Self.fit(image.size, in: imageSpace).width + 2 * Self.imagePadding)
        }
        return VStack(spacing: 0) {
            header
            Divider()
            content(fitting: imageSpace)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(width: min(width, space.width))
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
        // Clicks on the card don't reach the backdrop behind it.
        .contentShape(Rectangle())
        .onTapGesture {}
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                Text(lightbox.address.urlString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                let address = lightbox.address
                let title = lightbox.title
                store.closeImage(in: tab)
                store.open(address, title: title, inNewTab: true)
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .help("Open Image in New Tab")

            Button {
                store.closeImage(in: tab)
            } label: {
                Image(systemName: "xmark")
            }
            .help("Close Image (Esc)")
            .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.borderless)
        .imageScale(.large)
        .padding(.horizontal, 14)
        .frame(height: Self.headerHeight)
    }

    @ViewBuilder
    private func content(fitting space: CGSize) -> some View {
        switch lightbox.state {
        case .loading:
            ProgressView("Loading image…")
                .controlSize(.large)
                .frame(width: Self.minCardWidth, height: 200)
        case .failed(let message):
            VStack(spacing: 10) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Couldn't Load Image")
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try Again") { store.fetchImage(into: tab) }
                    .padding(.top, 4)
            }
            .padding(24)
            .frame(width: Self.minCardWidth)
        case .loaded(let image):
            let size = Self.fit(image.size, in: space)
            AnimatedImage(image: image)
                .frame(width: size.width, height: size.height)
                .padding(Self.imagePadding)
        }
    }

    /// The image's own size, scaled down (never up) to fit.
    static func fit(_ size: CGSize, in space: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: 1, height: 1) }
        let scale = min(1, max(space.width, 1) / size.width, max(space.height, 1) / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}

/// Shows an image in an NSImageView, which plays animated GIFs; SwiftUI's
/// Image shows only their first frame. Scales to whatever frame it's given.
struct AnimatedImage: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.isEditable = false
        for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            view.setContentCompressionResistancePriority(.defaultLow, for: orientation)
            view.setContentHuggingPriority(.defaultLow, for: orientation)
        }
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if view.image !== image { view.image = image }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? image.size.width, height: proposal.height ?? image.size.height)
    }
}
