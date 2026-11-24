import AppKit

// Generate macOS icon sizes from the checked-in artwork, preserving transparency.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let assets = root.appendingPathComponent("Assets", isDirectory: true)
let iconset = assets.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
guard let source = NSImage(contentsOf: assets.appendingPathComponent("AppIcon.png")) else {
    fatalError("无法读取应用图标")
}

for points in [16, 32, 128, 256, 512] {
    for density in [1, 2] {
        let size = points * density
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current!.imageInterpolation = .high
        source.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero,
            operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = density == 2 ? "@2x" : ""
        let path = iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: path)
    }
}
