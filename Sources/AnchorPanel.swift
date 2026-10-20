import AppKit

final class AnchorView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2))
        NSColor.black.withAlphaComponent(0.85).setFill()
        circle.fill()
        NSColor.white.setStroke()
        circle.lineWidth = 1.5
        circle.stroke()
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4)).fill()
        for angle in [0.0, Double.pi / 2, Double.pi, Double.pi * 1.5] {
            func point(_ along: Double, _ across: Double) -> NSPoint {
                NSPoint(x: center.x + cos(angle) * along - sin(angle) * across,
                        y: center.y + sin(angle) * along + cos(angle) * across)
            }
            let triangle = NSBezierPath()
            triangle.move(to: point(12, 0))
            triangle.line(to: point(7, 3))
            triangle.line(to: point(7, -3))
            triangle.close()
            triangle.fill()
        }
    }
}

final class AnchorPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 34, height: 34),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = AnchorView(frame: NSRect(x: 0, y: 0, width: 34, height: 34))
        setAccessibilityElement(false)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    func show(at point: CGPoint) {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        setFrameOrigin(NSPoint(x: point.x - 17, y: top - point.y - 17))
        orderFrontRegardless()
    }
}
