// Draws Holdfast's app icon (the mark in the sidebar: a violet rounded square with a white
// diamond) at every size an .iconset needs. Used by make_app.sh: swift scripts/make_icon.swift <dir>.
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let accent = NSColor(red: 0.40, green: 0.33, blue: 0.88, alpha: 1)
let accent2 = NSColor(red: 0.62, green: 0.36, blue: 0.93, alpha: 1)

func icon(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.28, yRadius: rect.width * 0.28)
    NSGradient(starting: accent, ending: accent2)!.draw(in: path, angle: -45)
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.36, weight: .semibold)
    if let sym = NSImage(systemSymbolName: "diamond.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: sym.size, flipped: false) { r in
            sym.draw(in: r); NSColor.white.withAlphaComponent(0.95).set(); r.fill(using: .sourceAtop); return true
        }
        let sz = tinted.size
        tinted.draw(in: NSRect(x: (s - sz.width) / 2, y: (s - sz.height) / 2, width: sz.width, height: sz.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! icon(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
