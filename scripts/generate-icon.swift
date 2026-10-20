import AppKit

// Vector artwork is rendered separately at each macOS icon size.
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
    NSGradient(starting: NSColor(srgbRed: 0.30, green: 0.34, blue: 0.91, alpha: 1),
               ending: NSColor(srgbRed: 0.10, green: 0.15, blue: 0.40, alpha: 1))!.draw(in: tile, angle: -90)
    NSColor.white.withAlphaComponent(0.16).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    let mouse = NSBezierPath(roundedRect: NSRect(x: 238, y: 222, width: 340, height: 580), xRadius: 170, yRadius: 170)
    NSColor.white.withAlphaComponent(0.08).setFill()
    mouse.fill()
    NSColor.white.setStroke()
    mouse.lineWidth = 32
    mouse.stroke()

    let seam = NSBezierPath()
    seam.move(to: NSPoint(x: 408, y: 790))
    seam.line(to: NSPoint(x: 408, y: 592))
    seam.lineWidth = 18
    seam.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.36).setStroke()
    seam.stroke()

    let wheel = NSBezierPath(roundedRect: NSRect(x: 378, y: 627, width: 60, height: 116), xRadius: 30, yRadius: 30)
    NSColor(srgbRed: 0.44, green: 0.96, blue: 0.85, alpha: 1).setFill()
    wheel.fill()

    let arrows = NSBezierPath()
    arrows.move(to: NSPoint(x: 694, y: 770))
    arrows.line(to: NSPoint(x: 694, y: 562))
    arrows.move(to: NSPoint(x: 634, y: 710))
    arrows.line(to: NSPoint(x: 694, y: 770))
    arrows.line(to: NSPoint(x: 754, y: 710))
    arrows.move(to: NSPoint(x: 694, y: 254))
    arrows.line(to: NSPoint(x: 694, y: 462))
    arrows.move(to: NSPoint(x: 634, y: 314))
    arrows.line(to: NSPoint(x: 694, y: 254))
    arrows.line(to: NSPoint(x: 754, y: 314))
    arrows.lineWidth = 32
    arrows.lineCapStyle = .round
    arrows.lineJoinStyle = .round
    NSColor.white.setStroke()
    arrows.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        try render(pixels: size * scale).write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
