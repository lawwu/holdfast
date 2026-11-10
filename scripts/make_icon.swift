import AppKit

// Compiled with the app's vector master by make_app.sh.
@main struct MakeIcon {
    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        for (name, pixels) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
                               ("128x128", 128), ("128x128@2x", 256), ("256x256", 256),
                               ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
            let png = HoldfastIcon.bitmap(size: pixels).representation(using: .png, properties: [:])!
            try png.write(to: out.appendingPathComponent("icon_\(name).png"))
        }
    }
}
