// Renders the iGhostty app icon into an .iconset directory.
// Usage: swift scripts/gen_icon.swift <output.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: gen_icon.swift <output.iconset>\n".data(using: .utf8)!)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func srgb(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

func draw(points: Int, scale: Int) {
    let px = points * scale
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let f = CGFloat(px)
    let inset = f * 0.098
    let rect = NSRect(x: inset, y: inset, width: f - inset * 2, height: f - inset * 2)
    let radius = rect.width * 0.2237
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    if let gradient = NSGradient(colors: [srgb(0x10121E), srgb(0x1E2340)]) {
        gradient.draw(in: squircle, angle: 90)
    }
    srgb(0x7AA2F7).withAlphaComponent(0.22).setStroke()
    squircle.lineWidth = max(1, f * 0.006)
    squircle.stroke()

    // Prompt chevron
    let glyphSize = f * 0.40
    let font = NSFont.monospacedSystemFont(ofSize: glyphSize, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: srgb(0x7AA2F7)]
    let glyph = "❯" as NSString
    let gs = glyph.size(withAttributes: attrs)
    glyph.draw(
        at: NSPoint(x: rect.minX + rect.width * 0.17, y: rect.midY - gs.height / 2),
        withAttributes: attrs
    )

    // Block cursor
    let curW = f * 0.135
    let curH = glyphSize * 0.72
    let cursorRect = NSRect(
        x: rect.minX + rect.width * 0.52,
        y: rect.midY - curH / 2 - f * 0.012,
        width: curW,
        height: curH
    )
    srgb(0x9ECE6A).setFill()
    NSBezierPath(roundedRect: cursorRect, xRadius: f * 0.018, yRadius: f * 0.018).fill()

    NSGraphicsContext.restoreGraphicsState()

    let suffix = scale == 2 ? "@2x" : ""
    let name = "icon_\(points)x\(points)\(suffix).png"
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: outDir.appendingPathComponent(name))
    }
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    draw(points: points, scale: scale)
}
print("iconset written to \(outDir.path)")
