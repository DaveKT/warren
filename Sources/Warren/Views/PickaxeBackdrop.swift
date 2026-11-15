import AppKit

/// The end-of-history backdrop: the Home page's ⛏️ in staggered rows,
/// tinted to the accent theme, on a pale tint of the theme's color. It
/// shows under the page when a swipe has nowhere further to go
/// (issue #7).
enum PickaxeBackdrop {
    /// Points between pickaxes, across and down; alternate rows shift by
    /// half of this.
    static let spacing: CGFloat = 104
    static let pickaxeSize: CGFloat = 40

    struct Colors {
        var pickaxe: NSColor
        var background: NSColor
    }

    /// Full-strength pickaxes on a pale tint (light mode) or a deep tint
    /// (dark mode) of the theme's color. Monochrome uses the app icon's red.
    static func colors(for theme: Theme, dark: Bool) -> Colors {
        let pickaxe: Int, background: Int
        switch theme {
        case .monochrome, .roots: (pickaxe, background) = (0xBB525B, 0xBB525B)
        case .moss: (pickaxe, background) = (0xCED552, 0xE9E275)
        case .sunset: (pickaxe, background) = (0xF26D50, 0xF2C43D)
        }
        let base = Theme.rgb(background)
        let tint = dark
            ? base.blended(withFraction: 0.86, of: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.11, alpha: 1))
            : base.blended(withFraction: 0.82, of: .white)
        return Colors(pickaxe: Theme.rgb(pickaxe), background: tint ?? base)
    }

    private struct Key: Hashable {
        var width: Int, height: Int, scale: CGFloat
        var theme: Theme, dark: Bool
    }

    @MainActor private static var cache: (key: Key, image: CGImage)?

    /// The backdrop at a size, drawn once and reused until the size, theme
    /// or light/dark mode changes.
    @MainActor
    static func image(size: CGSize, scale: CGFloat, theme: Theme, dark: Bool) -> CGImage? {
        let key = Key(width: Int(size.width.rounded(.up)), height: Int(size.height.rounded(.up)),
                      scale: scale, theme: theme, dark: dark)
        if let cache, cache.key == key { return cache.image }
        guard let image = draw(key) else { return nil }
        cache = (key, image)
        return image
    }

    private static func draw(_ key: Key) -> CGImage? {
        let colors = colors(for: key.theme, dark: key.dark)
        guard key.width > 0, key.height > 0,
              let pickaxe = tintedPickaxe(color: colors.pickaxe, lift: key.dark ? 0.6 : 0.4, scale: key.scale),
              let context = bitmapContext(width: key.width, height: key.height, scale: key.scale)
        else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: key.width, height: key.height)
        context.setFillColor(colors.background.cgColor)
        context.fill(bounds)

        // Staggered rows from the top-left, like the page: every row has a
        // pickaxe each `spacing` points, every other row shifted by half.
        let size = CGSize(width: pickaxeSize, height: pickaxeSize)
        var row = 0
        var y = bounds.maxY - spacing / 4
        while y > -spacing {
            var x = (row.isMultiple(of: 2) ? spacing / 4 : spacing * 3 / 4) - spacing
            while x < bounds.maxX + spacing {
                context.draw(pickaxe, in: CGRect(x: x - size.width / 2, y: y - size.height / 2,
                                                 width: size.width, height: size.height))
                x += spacing
            }
            y -= spacing / 2
            row += 1
        }
        return context.makeImage()
    }

    /// The ⛏️ emoji in one color: its shading kept as lightness, its own
    /// gray and brown replaced by the color. `lift` lightens the shadows
    /// first (0 keeps them black), so the handle reads as the color too.
    private static func tintedPickaxe(color: NSColor, lift: CGFloat, scale: CGFloat) -> CGImage? {
        let side = Int((pickaxeSize * 1.3).rounded(.up))
        guard let context = bitmapContext(width: side, height: side, scale: scale) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: side, height: side)

        // The emoji as the system draws it.
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let text = NSAttributedString(string: "⛏️", attributes: [.font: NSFont.systemFont(ofSize: pickaxeSize)])
        let textSize = text.size()
        text.draw(at: CGPoint(x: (rect.width - textSize.width) / 2, y: (rect.height - textSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        guard let emoji = context.makeImage() else { return nil }

        // Gray it, lighten the shadows, then color it: light parts become
        // the full color, dark parts a deeper shade of it. Each fill also
        // covers the empty corners, so the emoji's own shape cuts it back
        // out at the end.
        context.setBlendMode(.saturation)
        context.setFillColor(CGColor(gray: 0.5, alpha: 1))
        context.fill(rect)
        context.setBlendMode(.screen)
        context.setFillColor(CGColor(gray: lift, alpha: 1))
        context.fill(rect)
        context.setBlendMode(.multiply)
        context.setFillColor(color.cgColor)
        context.fill(rect)
        context.setBlendMode(.destinationIn)
        context.draw(emoji, in: rect)
        return context.makeImage()
    }

    /// A transparent sRGB bitmap measured in points at the given scale.
    private static func bitmapContext(width: Int, height: Int, scale: CGFloat) -> CGContext? {
        guard let context = CGContext(
            data: nil, width: Int(CGFloat(width) * scale), height: Int(CGFloat(height) * scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        return context
    }
}
