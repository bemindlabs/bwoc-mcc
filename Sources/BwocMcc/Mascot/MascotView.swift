import AppKit

/// The view drawn inside the floating mascot panel: the current sprite frame
/// with a gentle vertical bob, an optional emotion glyph above the head, and an
/// optional name caption. Pointer interaction (hover, pet-click, drag to
/// reposition, double-click to dismiss) is surfaced to `MascotAgent` via the
/// callbacks, which owns all behaviour.
final class MascotView: NSView {
    /// Index into `MascotSprite.frames` (0…7).
    var frameIndex: Int = 0 { didSet { if frameIndex != oldValue { needsDisplay = true } } }
    /// Vertical bob offset in points, applied on top of the sprite.
    var bob: CGFloat = 0 { didSet { needsDisplay = true } }
    /// Display name shown in the status-pill caption (agent id, "agent-" stripped),
    /// or nil for the generic desktop mascot. Reserves the caption band when set.
    var caption: String? { didSet { needsDisplay = true } }
    /// Whether the caption pill is currently drawn (hover-gated by MascotAgent).
    var showCaption = false { didSet { if showCaption != oldValue { needsDisplay = true } } }
    /// Live agent state painted into the caption pill (dot colour + unread badge).
    var captionRunning = false { didSet { needsDisplay = true } }
    var captionBlocked = false { didSet { needsDisplay = true } }
    var captionUnread = 0 { didSet { needsDisplay = true } }
    /// Optional emotion glyph (an emoji) floated above the head.
    var emote: String? { didSet { if emote != oldValue { needsDisplay = true } } }
    /// Extra emote bounce, 0…1, so a pet/alert can make the glyph pop.
    var emotePop: CGFloat = 0 { didSet { needsDisplay = true } }

    var onHover: ((Bool) -> Void)?
    var onPet: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    private let captionHeight: CGFloat = 18
    private let emoteZone: CGFloat = 22
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let frames = MascotSprite.frames
        guard !frames.isEmpty else { return }
        let img = frames[min(frameIndex, frames.count - 1)]

        // Vertical bands (AppKit y-up): caption | sprite | emote.
        let capRoom = caption == nil ? 0 : captionHeight
        let avail = NSRect(x: 0, y: capRoom,
                           width: bounds.width,
                           height: bounds.height - capRoom - emoteZone)
        let aspect = MascotSprite.aspect
        var w = avail.width
        var h = w / aspect
        if h > avail.height { h = avail.height; w = h * aspect }
        let x = avail.midX - w / 2
        let y = avail.minY + bob

        // Soft contact shadow grounds the mascot on the desktop.
        let shadowW = w * 0.55
        let shadow = NSBezierPath(ovalIn: NSRect(
            x: bounds.midX - shadowW / 2,
            y: avail.minY + 1,
            width: shadowW,
            height: h * 0.10))
        NSColor.black.withAlphaComponent(0.16).setFill()
        shadow.fill()

        img.draw(in: NSRect(x: x, y: y, width: w, height: h),
                 from: .zero, operation: .sourceOver, fraction: 1.0)

        if let emote, !emote.isEmpty {
            let pop = 1.0 + emotePop * 0.5
            let fontSize = 15.0 * pop
            let glyph = emote as NSString
            let gattrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize)]
            let gsize = glyph.size(withAttributes: gattrs)
            let gx = bounds.midX - gsize.width / 2
            let gy = y + h - gsize.height * 0.35 + emotePop * 3
            glyph.draw(at: NSPoint(x: gx, y: min(gy, bounds.height - gsize.height)),
                       withAttributes: gattrs)
        }

        if showCaption, let caption, !caption.isEmpty {
            drawCaptionPill(caption)
        }
    }

    /// A small status pill: a colour-coded dot (green running · grey idle · orange
    /// blocked), the name, and an unread badge — drawn in the reserved bottom band.
    private func drawCaptionPill(_ name: String) {
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let nameStr = name as NSString
        let nameSize = nameStr.size(withAttributes: nameAttrs)

        let dotD: CGFloat = 6
        let gap: CGFloat = 4
        let padX: CGFloat = 7, padY: CGFloat = 2

        let badge: NSString? = captionUnread > 0 ? ("✉\(captionUnread)" as NSString) : nil
        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.6, green: 0.85, blue: 1.0, alpha: 1),
        ]
        let badgeSize = badge?.size(withAttributes: badgeAttrs) ?? .zero

        var contentW = dotD + gap + nameSize.width
        if badge != nil { contentW += gap + badgeSize.width }
        let pillW = contentW + padX * 2
        let pillH = max(nameSize.height, dotD) + padY * 2
        let pillX = bounds.midX - pillW / 2
        let pillY = max(0, (captionHeight - pillH) / 2)

        let pill = NSBezierPath(roundedRect: NSRect(x: pillX, y: pillY, width: pillW, height: pillH),
                                xRadius: pillH / 2, yRadius: pillH / 2)
        NSColor.black.withAlphaComponent(0.62).setFill()
        pill.fill()

        var x = pillX + padX
        let midY = pillY + pillH / 2
        let dotColor: NSColor = captionBlocked ? .systemOrange : (captionRunning ? .systemGreen : NSColor(calibratedWhite: 0.65, alpha: 1))
        let dot = NSBezierPath(ovalIn: NSRect(x: x, y: midY - dotD / 2, width: dotD, height: dotD))
        dotColor.setFill(); dot.fill()
        x += dotD + gap

        nameStr.draw(at: NSPoint(x: x, y: midY - nameSize.height / 2), withAttributes: nameAttrs)
        x += nameSize.width + gap
        if let badge {
            badge.draw(at: NSPoint(x: x, y: midY - badgeSize.height / 2), withAttributes: badgeAttrs)
        }
    }

    // MARK: - Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.activeAlways, .mouseEnteredAndExited],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onDismiss?()
            return
        }
        // `performDrag` blocks until the mouse is released and moves the window if
        // the user actually dragged. Bracket it so the wander loop pauses, then
        // tell whether it ended as a click (a "pet") or a real reposition.
        let before = window?.frame.origin ?? .zero
        onDragBegan?()
        window?.performDrag(with: event)
        onDragEnded?()
        let after = window?.frame.origin ?? .zero
        if hypot(after.x - before.x, after.y - before.y) < 4 {
            onPet?()
        }
    }

    // A borderless, non-opaque panel needs an explicit hit area or clicks fall
    // through; the whole (small) panel is interactive.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
}
