import AppKit

/// One vector master for the Dock, sidebar and packaged .icns. Two ivory pages
/// and their binding form an H on a 1024-point evergreen canvas.
enum HoldfastIcon {
    static let mark = image(inset: false)

    static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                green: Double((hex >> 8) & 255) / 255,
                blue: Double(hex & 255) / 255, alpha: 1)
    }

    static func bitmap(size: Int, inset: Bool = true) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        let scale = CGFloat(size) / (inset ? 1024 : 864)
        transform.scale(by: scale)
        if !inset { transform.translateX(by: -80, yBy: -80) }
        transform.concat()

        let tile = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 198, yRadius: 198)
        NSGradient(colors: [color(0x447360), color(0x254C3F), color(0x16382F)])!.draw(in: tile, angle: -45)
        NSColor.white.withAlphaComponent(0.14).setStroke()
        let rim = NSBezierPath(roundedRect: NSRect(x: 82, y: 82, width: 860, height: 860), xRadius: 196, yRadius: 196)
        rim.lineWidth = 4
        rim.stroke()

        let left = NSBezierPath()
        left.move(to: NSPoint(x: 312, y: 268))
        left.line(to: NSPoint(x: 414, y: 268))
        left.line(to: NSPoint(x: 414, y: 770))
        left.line(to: NSPoint(x: 312, y: 770))
        left.curve(to: NSPoint(x: 282, y: 740), controlPoint1: NSPoint(x: 292, y: 770), controlPoint2: NSPoint(x: 282, y: 760))
        left.line(to: NSPoint(x: 282, y: 298))
        left.curve(to: NSPoint(x: 312, y: 268), controlPoint1: NSPoint(x: 282, y: 278), controlPoint2: NSPoint(x: 292, y: 268))
        left.close()
        let right = left.copy() as! NSBezierPath
        let mirror = AffineTransform(translationByX: 1024, byY: 0)
        var reflection = mirror
        reflection.scale(x: -1, y: 1)
        right.transform(using: reflection)
        let band = NSBezierPath(rect: NSRect(x: 414, y: 458, width: 196, height: 116))
        let silhouette = left.copy() as! NSBezierPath
        silhouette.append(right)
        silhouette.append(band)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color(0x071A13).withAlphaComponent(0.26)
        shadow.shadowOffset = NSSize(width: 0, height: -18 * scale)
        shadow.shadowBlurRadius = 14 * scale
        shadow.set()
        color(0xE8E5D5).setFill()
        silhouette.fill()
        NSGraphicsContext.restoreGraphicsState()
        let paper = NSGradient(starting: color(0xDDD9C7), ending: color(0xFFFEF8))!
        paper.draw(in: left, angle: 90)
        paper.draw(in: right, angle: 90)
        NSGradient(colors: [color(0xDDD9C7), color(0xFFFDF3), color(0xD4D0BC)])!.draw(in: band, angle: 0)
        // Fine page edges disappear at small sizes to keep the H crisp.
        if size >= 64 {
            color(0x183F32).withAlphaComponent(0.13).setStroke()
            let edges = NSBezierPath()
            for x: CGFloat in [394, 630] {
                edges.move(to: NSPoint(x: x, y: 292))
                edges.line(to: NSPoint(x: x, y: 747))
            }
            edges.lineWidth = 5
            edges.stroke()
        }
        return bitmap
    }

    static func image(inset: Bool = true) -> NSImage {
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        for size in [32, 64, 128, 256, 512, 1024] { image.addRepresentation(bitmap(size: size, inset: inset)) }
        return image
    }
}
