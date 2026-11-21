import AppKit

/// A Desktop window's size (David, 2026-11-21, "option 2"): the other Mac's resolution stays as it is
/// and the Viewer's window adapts to it, as Screen Sharing's standard mode does.
/// - Keep the Desktop's Shape (a setting, on by default): while on, a Desktop window's picture area
///   keeps the stream's proportions as it is resized (AppKit's `contentAspectRatio`), so there are no
///   black bars. Off: free resizing, the picture fitted with bars, as before.
/// - Actual Size: one of the other Mac's points is one of this Mac's; fitted to the screen when that
///   is too big for it.
/// - Fit to Screen: the largest window of the Desktop's shape inside the screen's visible frame (the
///   green button and a double-click on the title bar too).
/// App windows are unchanged: the other Mac already sizes those to the window here (its viewport).
/// Nothing new is sent: the sizes come from the frame the Desktop's stream already carries, its
/// displays' sizes where the other Mac lists them, and the Resolution setting. Pure but for the
/// setting, so `Tests/checks` could check it with swiftc.
enum DesktopSizing {
    static let key = "SillClient.keepDesktopShape"
    /// Posted when Keep the Desktop's Shape changes (every Desktop window, the launcher and the menus follow).
    static let changed = Notification.Name("SillClient.desktopShapeChanged")

    static var keepsShape: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    enum Command: String { case actual, fit }

    /// The other Mac's Desktop in its own points, from the frame's pixels and the Resolution
    /// (`captureScale`: 2 Retina, 1 Standard). The other Mac captures at the lesser of the Resolution
    /// and the display's own scale (CaptureScale on the host), which a frame alone can't tell apart:
    /// a Retina display 1512 points wide sends 3024 pixels, a 1x one 3024 points wide sends the same.
    /// So a frame that would make a display narrower than 1300 points at 2x is taken as a 1x display
    /// (no Mac display is that narrow at 2x but an 11-inch MacBook Air's 1366 × 768, which is at 1x):
    /// a 1920 × 1080 virtual machine's display and a 2560 × 1440 monitor at 1x come out right. Where
    /// the other Mac lists its displays, their sizes are used instead and this is never needed.
    static func points(frame: CGSize, captureScale: Double?) -> CGSize {
        let knob = CGFloat(captureScale ?? 2)
        guard knob > 1, frame.width / knob >= 1300 else { return frame }
        return CGSize(width: frame.width / knob, height: frame.height / knob)
    }

    /// The largest size of `shape`'s proportions inside `room`, whole points.
    static func fit(shape: CGSize, room: CGSize) -> CGSize {
        guard shape.width > 0, shape.height > 0, room.width > 0, room.height > 0 else { return room }
        let k = min(room.width / shape.width, room.height / shape.height)
        return CGSize(width: (shape.width * k).rounded(.down), height: (shape.height * k).rounded(.down))
    }

    /// Actual Size: `points` when it fits `room`, else fitted to it (and how much it was scaled, 0 to 1).
    static func actual(points: CGSize, room: CGSize) -> (size: CGSize, scale: CGFloat) {
        if points.width <= room.width, points.height <= room.height { return (points, 1) }
        let size = fit(shape: points, room: room)
        return (size, points.width > 0 ? size.width / points.width : 1)
    }

    /// The picture area for a width, at `shape`'s proportions.
    static func keepingWidth(_ width: CGFloat, shape: CGSize) -> CGSize {
        guard shape.width > 0 else { return CGSize(width: width, height: width * 10 / 16) }
        return CGSize(width: width, height: (width * shape.height / shape.width).rounded())
    }
}

/// The menus' Keep the Desktop's Shape item: a target that flips the setting and ticks the item.
final class DesktopShapeItem: NSObject, NSMenuItemValidation {
    static let shared = DesktopShapeItem()
    static let title = "Keep the Desktop’s Shape"

    @objc func toggle(_ sender: Any?) { DesktopSizing.keepsShape.toggle() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        item.state = DesktopSizing.keepsShape ? .on : .off
        return true
    }

    /// The three items, for the app menu and a toolbar's Quality menu.
    static func items() -> [NSMenuItem] {
        let actual = NSMenuItem(title: "Actual Size", action: #selector(StreamWindow.actualSize(_:)), keyEquivalent: "0")
        let fit = NSMenuItem(title: "Fit to Screen", action: #selector(StreamWindow.fitToScreen(_:)), keyEquivalent: "0")
        fit.keyEquivalentModifierMask = [.command, .option]
        let keep = NSMenuItem(title: title, action: #selector(toggle(_:)), keyEquivalent: "")
        keep.target = shared
        keep.state = DesktopSizing.keepsShape ? .on : .off
        return [actual, fit, keep]
    }
}
