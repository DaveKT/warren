import AppKit
import SwiftUI

/// Accent colors, drawn from the Gopher themes
/// (docs/archive/Feature_Requests.md).
enum Palette {
    /// Gopher Moss #ac7838.
    static let moss = NSColor(srgbRed: 0xAC / 255, green: 0x78 / 255, blue: 0x38 / 255, alpha: 1)

    /// Gopher Moss olive #89865b.
    static let mossOlive = NSColor(srgbRed: 0x89 / 255, green: 0x86 / 255, blue: 0x5B / 255, alpha: 1)

    /// A subtle moss fill for the active tab. Dark mode needs a little more
    /// of it to read against the darker background.
    static let mossWashColor = NSColor(name: nil) { appearance in
        moss.withAlphaComponent(isDark(appearance) ? 0.32 : 0.22)
    }
    static let mossWash = Color(nsColor: mossWashColor)

    /// Find matches other than the current one. Light mode keeps the subtle
    /// moss wash over the page's own text colors. In dark mode that wash
    /// stood out from the page at only 1.6:1, so it's solid moss olive with
    /// black text instead (4.5:1 against the page, 5.6:1 for the text) —
    /// see `findMatchUsesDarkText`.
    static let findMatchColor = NSColor(name: nil) { appearance in
        isDark(appearance) ? mossOlive : moss.withAlphaComponent(0.22)
    }

    /// Whether find matches get black text: yes on the solid dark-mode fill,
    /// no in light mode, where matches keep the page's text and link colors.
    static func findMatchUsesDarkText(in appearance: NSAppearance) -> Bool {
        isDark(appearance)
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

/// Accent themes, chosen in Settings → Appearance. Monochrome keeps
/// Warren's standard look; the Gopher themes recolor, sparingly, the menu
/// links (and a hovered link's icon) and the active tab's fill. Link colors
/// are lightened or darkened per mode to read at 4.5:1 or better against
/// the page. Find highlights keep their own colors in every theme.
enum Theme: String, CaseIterable, Identifiable {
    case monochrome, moss, sunset, roots

    static let storageKey = "theme"

    var id: Self { self }

    var name: String {
        switch self {
        case .monochrome: return "Monochrome"
        case .moss: return "Gopher Moss"
        case .sunset: return "Gopher Sunset"
        case .roots: return "Gopher Roots"
        }
    }

    /// The theme's five colors (docs/archive/Feature_Requests.md), for Settings.
    var swatches: [NSColor] {
        switch self {
        case .monochrome: return []
        case .moss: return [0x5D5A2F, 0x89865B, 0xAC7838, 0xCED552, 0xE9E275].map(Self.rgb)
        case .sunset: return [0x3E9CBF, 0xA7ECF2, 0xF2C43D, 0xF17C37, 0xF26D50].map(Self.rgb)
        case .roots: return [0x555559, 0xC9BCA4, 0xBB525B, 0xB8893D, 0x92B558].map(Self.rgb)
        }
    }

    /// Menu links, and the icon of the link under the pointer.
    var linkColor: NSColor {
        switch self {
        case .monochrome: return .controlAccentColor
        // #5d5a2f (7.1:1) light; #ced552 (10.5:1) dark.
        case .moss: return Self.adaptive(light: 0x5D5A2F, dark: 0xCED552)
        // #3e9cbf darkened to #307995 (4.9:1) light; #3e9cbf (5.3:1) dark.
        case .sunset: return Self.adaptive(light: 0x307995, dark: 0x3E9CBF)
        // #bb525b (4.7:1) light; lightened to #c77178 (4.8:1) dark.
        case .roots: return Self.adaptive(light: 0xBB525B, dark: 0xC77178)
        }
    }

    /// The active tab's subtle fill.
    var tabWash: Color {
        switch self {
        case .monochrome, .moss: return Palette.mossWash
        case .sunset: return Color(nsColor: Self.wash(0xF17C37))
        case .roots: return Color(nsColor: Self.wash(0xB8893D))
        }
    }

    private static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func adaptive(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { Palette.isDark($0) ? rgb(dark) : rgb(light) }
    }

    /// Same strengths as the Moss active-tab fill.
    private static func wash(_ hex: Int) -> NSColor {
        NSColor(name: nil) { rgb(hex).withAlphaComponent(Palette.isDark($0) ? 0.32 : 0.22) }
    }
}
