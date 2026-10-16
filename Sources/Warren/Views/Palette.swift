import AppKit
import SwiftUI

/// Accent colors, drawn from the planned Gopher themes
/// (docs/Feature_Requests.md).
enum Palette {
    /// Gopher Moss #ac7838.
    static let moss = NSColor(srgbRed: 0xAC / 255, green: 0x78 / 255, blue: 0x38 / 255, alpha: 1)

    /// A subtle moss fill for the active tab and find matches. Dark mode
    /// needs a little more of it to read against the darker background.
    static let mossWash = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return moss.withAlphaComponent(isDark ? 0.32 : 0.22)
    })
}
