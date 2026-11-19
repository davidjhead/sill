import AppKit

/// The status item's image: design/ViewerIcon.svg reduced to a menu bar template, as Sill.app's
/// StatusGlyph is its icon's. The iMac is an outline, and the MacBook sits tilted in front of it as in
/// the icon, cut out of the iMac behind, with the streamed window on its screen.
///
/// Drawn in code from the SVG's own coordinates, so there is no asset to keep in sync, and marked as a
/// template so the menu bar tints it for light and dark bars and highlights it when the menu is open.
enum ViewerGlyph {
    /// 18 pt tall: 16 pt of drawing and a point above and below, like the system's own items.
    static let size = NSSize(width: 21, height: 18)

    static func image() -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(in: ctx)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Sill Viewer"
        return image
    }

    // MARK: Geometry, in ViewerIcon.svg units (1024 grid; the 51-unit shift of its group applied)

    /// Units → points: the drawing spans the iMac's body top (201) to the MacBook's deck bottom (about
    /// 836 once tilted) in 16 pt, centred in the image.
    private static let top: CGFloat = 201, bottom: CGFloat = 836
    private static let scale: CGFloat = 16 / (bottom - top)
    private static let origin = CGPoint(x: 512 - size.width / scale / 2, y: top - 1 / scale)

    private static func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: (x - origin.x) * scale, y: (y - origin.y) * scale)
    }

    private static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(origin: point(x, y), size: CGSize(width: w * scale, height: h * scale))
    }

    private static func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: radius * scale, cornerHeight: radius * scale, transform: nil)
    }

    /// The MacBook's lid, its hinge edge square: the SVG's path, as points.
    private static func lid(inset: CGFloat = 0) -> CGPath {
        let p = CGMutablePath(), r: CGFloat = 34 - inset
        let l = 292 + inset, t = 481 + inset, rt = 732 - inset, b: CGFloat = 781
        p.move(to: point(l, b))
        p.addLine(to: point(l, t + r))
        p.addQuadCurve(to: point(l + r, t), control: point(l, t))
        p.addLine(to: point(rt - r, t))
        p.addQuadCurve(to: point(rt, t + r), control: point(rt, t))
        p.addLine(to: point(rt, b))
        return p
    }

    /// The MacBook's deck, under the lid: the SVG's trapezoid.
    private static func deck() -> CGPath {
        let p = CGMutablePath()
        p.move(to: point(240, 781)); p.addLine(to: point(784, 781))
        p.addLine(to: point(756, 823)); p.addLine(to: point(268, 823))
        p.closeSubpath()
        return p
    }

    private static func draw(in ctx: CGContext) {
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)

        // The iMac: body outline (stroked inside the SVG's 672×400 rectangle), neck and foot.
        let stroke: CGFloat = 50                              // about 1.3 pt
        ctx.setLineWidth(stroke * scale)
        ctx.addPath(rounded(rect(176 + stroke / 2, 201 + stroke / 2, 672 - stroke, 400 - stroke), 58 - stroke / 2))
        ctx.strokePath()
        ctx.fill(rect(480, 597, 64, 48))
        ctx.addPath(rounded(rect(372, 639, 280, 36), 18))
        ctx.fillPath()

        // The MacBook, tilted -4° about the SVG's own centre for it.
        let pivot = point(512, 651)
        ctx.saveGState()
        ctx.translateBy(x: pivot.x, y: pivot.y)
        ctx.rotate(by: -4 * .pi / 180)
        ctx.translateBy(x: -pivot.x, y: -pivot.y)

        // Cut out of the iMac behind: the lid and deck with a margin, so the two never touch.
        let gap: CGFloat = 36
        ctx.setBlendMode(.clear)
        ctx.addPath(lid()); ctx.closePath()
        ctx.addPath(deck())
        ctx.setLineWidth(gap * 2 * scale)
        ctx.setLineJoin(.round)
        ctx.drawPath(using: .fillStroke)
        ctx.setBlendMode(.normal)

        // The lid: an outline whose screen shows the streamed window.
        let border: CGFloat = 40                              // about 1 pt
        ctx.setLineWidth(border * scale)
        ctx.setLineJoin(.miter)
        ctx.addPath(lid(inset: border / 2))
        ctx.strokePath()
        ctx.addPath(rounded(rect(292 + border + 34, 481 + border + 34, 440 - 2 * (border + 34), 300 - border - 2 * 34), 14))
        ctx.fillPath()

        // The deck.
        ctx.addPath(deck())
        ctx.fillPath()
        ctx.restoreGState()
    }
}
