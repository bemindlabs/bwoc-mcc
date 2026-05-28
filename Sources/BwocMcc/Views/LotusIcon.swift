import AppKit

/// Flat, monochrome lotus rendered as a template `NSImage` — the canonical,
/// reliably-visible menu-bar icon. (A raw SwiftUI `Shape` in a MenuBarExtra
/// label renders blank, so we draw the petals into an NSImage instead.)
enum LotusIcon {
    static let image: NSImage = {
        let side: CGFloat = 18
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let h = rect.height
            let w = rect.width
            // Shared anchor near the bottom-centre; petals fan upward (AppKit y-up).
            let base = CGPoint(x: rect.midX, y: rect.minY + h * 0.10)

            // (angle from vertical°, length · h, width · w) — tall centre, short sides.
            let petals: [(Double, CGFloat, CGFloat)] = [
                (   0, 0.82, 0.30),
                ( -32, 0.66, 0.27),
                (  32, 0.66, 0.27),
                ( -62, 0.50, 0.24),
                (  62, 0.50, 0.24),
            ]

            let path = NSBezierPath()
            for (deg, lenF, widF) in petals {
                let t = deg * .pi / 180
                let dirx = CGFloat(sin(t)), diry = CGFloat(cos(t))   // "up" is +y
                let perx = CGFloat(cos(t)), pery = CGFloat(-sin(t))  // perpendicular
                let len = lenF * h
                let wid = widF * w
                let tip = CGPoint(x: base.x + dirx * len, y: base.y + diry * len)
                let mid = CGPoint(x: base.x + dirx * len * 0.5, y: base.y + diry * len * 0.5)
                let left = CGPoint(x: mid.x + perx * wid * 0.5, y: mid.y + pery * wid * 0.5)
                let right = CGPoint(x: mid.x - perx * wid * 0.5, y: mid.y - pery * wid * 0.5)
                path.move(to: base)
                path.curve(to: tip, controlPoint1: left, controlPoint2: left)
                path.curve(to: base, controlPoint1: right, controlPoint2: right)
                path.close()
            }
            path.windingRule = .nonZero
            NSColor.black.setFill()
            path.fill()
            return true
        }
        img.isTemplate = true
        return img
    }()
}
