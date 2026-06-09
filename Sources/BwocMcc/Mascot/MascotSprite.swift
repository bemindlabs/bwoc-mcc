import AppKit

/// The mascot's 8-view turnaround atlas, sliced into per-direction frames.
///
/// `mascot_sheet.png` is one horizontal row of 8 equal cells produced by
/// `scripts/gen-mascot-sheet.py` from the brand turnaround contact-sheet. The
/// cells are ordered by yaw: 0°, 45°, 90°, … 315°, where 0° faces the viewer
/// (front), 90° faces screen-right, 180° faces away (back), 270° faces
/// screen-left.
enum MascotSprite {
    /// Eight frames, index `i` == view angle `i * 45°`.
    static let frames: [NSImage] = sliceAtlas()

    /// Native pixel aspect ratio (width / height) of a single frame, so the
    /// floating window can keep the mascot undistorted.
    static let aspect: CGFloat = {
        guard let f = frames.first, f.size.height > 0 else { return 1 }
        return f.size.width / f.size.height
    }()

    /// Frame index for a desktop movement heading.
    ///
    /// `heading` is `atan2(dy, dx)` in screen coordinates (x right+, y **down+**,
    /// i.e. AppKit-flipped for movement): 0 = moving right, 90° = moving down
    /// toward the viewer, 180° = left, 270° = up/away. The front view (0°) should
    /// show when the mascot walks down toward the viewer, so view = 90° − heading.
    static func frameIndex(headingDegrees heading: Double) -> Int {
        let view = (90.0 - heading).truncatingRemainder(dividingBy: 360)
        let norm = (view + 360).truncatingRemainder(dividingBy: 360)
        return Int((norm / 45.0).rounded()) % 8
    }

    /// The front-facing (idle) frame.
    static var front: NSImage { frames.isEmpty ? NSImage() : frames[0] }

    private static func sliceAtlas() -> [NSImage] {
        guard
            let url = atlasURL(),
            let sheet = NSImage(contentsOf: url),
            let cg = sheet.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return []
        }
        let count = 8
        let cellW = cg.width / count
        let cellH = cg.height
        var out: [NSImage] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let rect = CGRect(x: i * cellW, y: 0, width: cellW, height: cellH)
            guard let crop = cg.cropping(to: rect) else { continue }
            out.append(NSImage(cgImage: crop, size: NSSize(width: cellW, height: cellH)))
        }
        return out
    }

    /// Resolve `mascot_sheet.png`. In the packaged .app it lives in
    /// Contents/Resources (Bundle.main); for `swift run` / unit runs it's found
    /// relative to this source file's Resources sibling directory.
    private static func atlasURL() -> URL? {
        if let u = Bundle.main.url(forResource: "mascot_sheet", withExtension: "png") {
            return u
        }
        // Dev fallback: Sources/BwocMcc/Mascot/MascotSprite.swift → ../Resources.
        let dev = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // Mascot/
            .deletingLastPathComponent()        // BwocMcc/
            .appendingPathComponent("Resources/mascot_sheet.png")
        return FileManager.default.fileExists(atPath: dev.path) ? dev : nil
    }
}
