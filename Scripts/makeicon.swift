// Renders the Warren app icon (a pick ⛏️, U+26CF U+FE0F, for digging
// through Gopherspace) on a rounded warm background to a 1024x1024 PNG.
// Usage: swift Scripts/makeicon.swift <output.png>
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size = NSSize(width: 1024, height: 1024)

let image = NSImage(size: size)
image.lockFocus()

let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.55, green: 0.40, blue: 0.26, alpha: 1.0),
    NSColor(calibratedRed: 0.33, green: 0.22, blue: 0.13, alpha: 1.0),
])
gradient?.draw(in: path, angle: -90)

let emoji = "\u{26CF}\u{FE0F}" as NSString // ⛏️ pick
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 560)]
let textSize = emoji.size(withAttributes: attributes)
emoji.draw(at: NSPoint(x: (size.width - textSize.width) / 2,
                       y: (size.height - textSize.height) / 2),
           withAttributes: attributes)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("failed to render icon\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
