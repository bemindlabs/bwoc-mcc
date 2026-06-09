import AppKit

/// A speech bubble rendered in its own click-through panel, floated just above
/// the mascot. Kept separate from the mascot panel so the (large, mostly empty)
/// bubble never intercepts clicks meant for the desktop. `MascotAgent` sizes the
/// panel via `size(for:)` and positions it each tick.
final class MascotBubbleView: NSView {
    var text: String = "" { didSet { needsDisplay = true } }

    static let maxWidth: CGFloat = 220
    static let padX: CGFloat = 9
    static let padY: CGFloat = 6
    static let tail: CGFloat = 7          // downward pointer height
    static let radius: CGFloat = 9
    static let font = NSFont.systemFont(ofSize: 11, weight: .medium)

    override var isFlipped: Bool { false }

    /// Lay out the wrapped text rect for a given full text.
    private static func textBounds(_ s: String) -> NSRect {
        let inner = maxWidth - padX * 2
        return (s as NSString).boundingRect(
            with: NSSize(width: inner, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
    }

    /// Total panel size needed to show `s` (bubble body + tail).
    static func size(for s: String) -> NSSize {
        let b = textBounds(s)
        return NSSize(width: ceil(b.width) + padX * 2,
                      height: ceil(b.height) + padY * 2 + tail)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        let body = NSRect(x: 0, y: Self.tail,
                          width: bounds.width, height: bounds.height - Self.tail)

        let path = NSBezierPath(roundedRect: body, xRadius: Self.radius, yRadius: Self.radius)
        // Downward tail at the bottom-centre, pointing at the mascot's head.
        let cx = bounds.midX
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: cx - Self.tail, y: Self.tail + 0.5))
        tail.line(to: NSPoint(x: cx, y: 0))
        tail.line(to: NSPoint(x: cx + Self.tail, y: Self.tail + 0.5))
        tail.close()
        path.append(tail)

        NSColor.black.withAlphaComponent(0.30).setStroke()
        NSColor(calibratedWhite: 1.0, alpha: 0.96).setFill()
        path.fill()
        path.lineWidth = 1
        path.stroke()

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.black.withAlphaComponent(0.82),
            .paragraphStyle: para,
        ]
        let textRect = NSRect(
            x: Self.padX, y: Self.tail + Self.padY,
            width: bounds.width - Self.padX * 2,
            height: bounds.height - Self.tail - Self.padY * 2)
        (text as NSString).draw(with: textRect,
                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                attributes: attrs)
    }
}
