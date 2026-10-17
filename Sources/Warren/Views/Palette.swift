import AppKit
import SwiftUI

/// Accent colors, drawn from the planned Gopher themes
/// (docs/Feature_Requests.md).
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
