import AppKit

// Rebuild the application icon with macOS drawing APIs. No external assets required.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let assets = root.appendingPathComponent("Assets", isDirectory: true)
let iconset = assets.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func render(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let scale = CGFloat(size) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)

    let tile = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0, 0.03, 0.04, 0.26)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0.07, 0.10, 0.13).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: color(0.16, 0.20, 0.23), ending: color(0.055, 0.08, 0.10))!
        .draw(in: tile, angle: -90)
    let rim = NSBezierPath(roundedRect: NSRect(x: 99, y: 99, width: 826, height: 826), xRadius: 183, yRadius: 183)
    color(0.80, 0.95, 0.95, 0.14).setStroke()
    rim.lineWidth = 3
    rim.stroke()

    let ring = NSBezierPath(ovalIn: NSRect(x: 284, y: 284, width: 456, height: 456))
    ring.lineWidth = 46
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color(0.12, 0.93, 0.65, 0.24)
    glow.shadowBlurRadius = 30
    glow.shadowOffset = .zero
    glow.set()
    color(0.22, 0.88, 0.67).setStroke()
    ring.stroke()
    NSGraphicsContext.restoreGraphicsState()

    // Clip a gradient to the ring for a crisp mark with a subtle light direction.
    context.cgContext.saveGState()
    context.cgContext.addEllipse(in: CGRect(x: 261, y: 261, width: 502, height: 502))
    context.cgContext.addEllipse(in: CGRect(x: 307, y: 307, width: 410, height: 410))
    context.cgContext.clip(using: .evenOdd)
    NSGradient(starting: color(0.52, 1.00, 0.80), ending: color(0.06, 0.72, 0.57))!
        .draw(in: NSRect(x: 256, y: 256, width: 512, height: 512), angle: -60)
    context.cgContext.restoreGState()

    let dot = NSBezierPath(ovalIn: NSRect(x: 452, y: 452, width: 120, height: 120))
    NSGradient(starting: color(0.64, 1.00, 0.85), ending: color(0.17, 0.86, 0.64))!
        .draw(in: dot, angle: -75)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let suffix = density == 2 ? "@2x" : ""
        let name = "icon_\(points)x\(points)\(suffix).png"
        try render(size: points * density).write(to: iconset.appendingPathComponent(name))
    }
}
try render(size: 1024).write(to: assets.appendingPathComponent("AppIcon.png"))
