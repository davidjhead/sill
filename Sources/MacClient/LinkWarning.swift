import Foundation
import StreamProtocol

/// The other Mac's word that the link can't carry the quality (`HostSettingsState.link`, "behind": it
/// withholds frames, so every picture that gets through is a whole new frame and they fall seconds
/// behind; picks and launches wait behind them too). The Viewer says so as the iPhone's stream screen
/// does (AwayCopy.callout), with the lower quality the Mac recommends a click away: the launcher's
/// banner and each window's toolbar (WindowToolbar). Gone as soon as the Mac reports the link keeping up.
enum LinkWarning {
    #if DEBUG
    /// The harness's report in place of the Mac's (`linkwarning behind|clear`): a test host on loopback
    /// never falls behind.
    static var testLink: LinkReport?
    #endif

    /// What to show now, or nil while the link keeps up. Main thread.
    static func callout(_ client: StreamClient) -> AwayCopy.Callout? {
        var link = client.settings.host?.link
        #if DEBUG
        if let testLink { link = testLink }
        #endif
        return AwayCopy.callout(link: link, away: client.settings.host?.away, mac: client.macName)
    }
}

import AppKit

/// The link warning as a toast inside a session's window (David, 2026-11-21: "a toast notification in
/// the session … the ability to change to that suggested setting by tapping on the toast … dismiss
/// within 5 seconds … but remain in the viewer"): at the top centre of the picture, over it, for 5 s,
/// then it fades. A click anywhere on it applies the recommended quality; with nothing to recommend it
/// only says why. The launcher's banner and the toolbar's warning stay while the link is behind.
/// Shown once for each warning (StreamWindows.updateLinkToast): again only when the warning changes or
/// comes back after the link kept up. Main thread.
final class LinkToast: NSVisualEffectView {
    /// How long it shows before it fades.
    static let shownFor: TimeInterval = 5
    private let onPress: () -> Void
    private var hideWork: DispatchWorkItem?

    init(_ warning: AwayCopy.Callout, onPress: @escaping () -> Void) {
        self.onPress = onPress
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.6).cgColor
        appearance = NSAppearance(named: .darkAqua)

        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        icon.contentTintColor = .systemOrange
        let title = NSTextField(labelWithString: "Pictures are falling behind")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let text = NSTextField(wrappingLabelWithString: warning.text)
        text.font = .systemFont(ofSize: 12)
        text.textColor = .secondaryLabelColor
        text.preferredMaxLayoutWidth = 300
        let words = NSStackView(views: [title, text])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 2
        var views: [NSView] = [icon, words]
        if let button = warning.button {
            let label = NSTextField(labelWithString: button.title)
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .black
            label.translatesAutoresizingMaskIntoConstraints = false
            let pill = NSView()
            pill.wantsLayer = true
            pill.layer?.backgroundColor = NSColor.white.cgColor
            pill.layer?.cornerRadius = 11
            pill.translatesAutoresizingMaskIntoConstraints = false
            pill.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: pill.centerXAnchor), label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
                pill.widthAnchor.constraint(equalTo: label.widthAnchor, constant: 24), pill.heightAnchor.constraint(equalToConstant: 22),
            ])
            views.append(pill)
            toolTip = "Click to use \(button.title.replacingOccurrences(of: "Use ", with: "")) on the other Mac, for every device"
        }
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Pictures are falling behind. \(warning.text)" + (warning.button.map { " \($0.spoken)" } ?? ""))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        press()
    }
    override func accessibilityPerformPress() -> Bool { press(); return true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    /// The toast's click: the recommended quality, then gone.
    func press() {
        onPress()
        hide()
    }

    /// Over `container`, at its top centre, above the picture; fades after `shownFor`.
    func show(in container: NSView) {
        // A frame, not constraints: the stream view put back into the window raises the toast again
        // (StreamWindows.attach), which a constraint to its container would not survive.
        let size = fittingSize
        let width = min(size.width, max(container.bounds.width - 28, 120))
        let top = container.isFlipped ? 14 : container.bounds.height - size.height - 14
        frame = NSRect(x: ((container.bounds.width - width) / 2).rounded(), y: top, width: width, height: size.height)
        autoresizingMask = container.isFlipped ? [.minXMargin, .maxXMargin, .maxYMargin] : [.minXMargin, .maxXMargin, .minYMargin]
        container.addSubview(self, positioned: .above, relativeTo: nil)
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; animator().alphaValue = 1 }
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: accessibilityLabel() ?? "", .priority: NSAccessibilityPriorityLevel.high.rawValue])
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shownFor, execute: work)
    }

    /// Fades out and goes (at once from a press, a warning that cleared, or a window that closed).
    func hide() {
        hideWork?.cancel(); hideWork = nil
        guard superview != nil else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; animator().alphaValue = 0 }) { [weak self] in
            self?.removeFromSuperview()
        }
    }
}
