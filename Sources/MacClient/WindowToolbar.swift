import AppKit
import StreamProtocol

/// A stream window's toolbar (David, 2026-11-20: "expand the toolbar across the top of both desktop and
/// app", like a virtual machine app's): this Mac's own compact unified toolbar, so the traffic lights,
/// the title, a drag to move, a double click to zoom and full screen's hidden toolbar are AppKit's. Its
/// buttons, at the right:
/// - ⌘ keys: this window's Capture shortcuts (⌘Tab, ⌘Space and the others macOS keeps) to the other Mac,
///   on until turned off, paused while another window or app has the keyboard (SystemKeyTap: the tap
///   is there only while this window's picture has the keyboard, and every held key is let go when it
///   loses it). Lit, with "Keys to <Mac>", while on. A new window starts as the launcher's Capture
///   shortcuts switch says, and that switch sets every open window.
/// - Gestures (a Desktop only): Mission Control, App Exposé, Spaces, Show Desktop, as the menu bar menu.
/// - Quality: the quality, resolution and frame rate (the other Mac's, for every device).
/// - Refresh: the other Mac makes its hidden displays again, where it has them.
/// - Launcher.
/// Main thread.
final class WindowToolbar: NSObject, NSToolbarDelegate, NSMenuDelegate {
    private weak var window: StreamWindow?
    private let client: StreamClient
    private let desktop: Bool
    var onRefresh: (() -> Void)?
    var onLauncher: (() -> Void)?
    private let keysButton = NSButton()
    private let qualityMenu = NSMenu()
    private let gestureMenu = NSMenu()
    private weak var refreshItem: NSToolbarItem?

    static let keys = NSToolbarItem.Identifier("sill.keys")
    static let gestures = NSToolbarItem.Identifier("sill.gestures")
    static let quality = NSToolbarItem.Identifier("sill.quality")
    static let refresh = NSToolbarItem.Identifier("sill.refresh")
    static let launcher = NSToolbarItem.Identifier("sill.launcher")

    init(window: StreamWindow, client: StreamClient, desktop: Bool) {
        self.window = window
        self.client = client
        self.desktop = desktop
        super.init()
        keysButton.bezelStyle = .toolbar
        keysButton.setButtonType(.pushOnPushOff)
        keysButton.image = NSImage(systemSymbolName: "command", accessibilityDescription: "Command Keys to the Other Mac")
        keysButton.imagePosition = .imageLeading
        keysButton.target = self
        keysButton.action = #selector(keysPressed)
        keysButton.setAccessibilityLabel("Command Keys to the Other Mac")
        qualityMenu.delegate = self
        gestureMenu.delegate = self
        let toolbar = NSToolbar(identifier: desktop ? "sill.stream.desktop" : "sill.stream.app")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
        NotificationCenter.default.addObserver(self, selector: #selector(update), name: SystemKeyTap.changed, object: nil)
        update()
    }

    var items: [NSToolbarItem.Identifier] {
        [.flexibleSpace, Self.keys] + (desktop ? [Self.gestures] : []) + [Self.quality, Self.refresh, Self.launcher]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { items }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { items }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case Self.keys:
            let item = NSToolbarItem(itemIdentifier: id)
            item.view = keysButton
            item.label = "Command Keys"
            return item
        case Self.gestures:
            return menuItem(id, "rectangle.3.group", "Mission Control and Gestures", gestureMenu)
        case Self.quality:
            return menuItem(id, "chart.bar", "Quality", qualityMenu)
        case Self.refresh:
            let item = button(id, "arrow.clockwise", "Refresh Picture", #selector(refreshPressed))
            item.toolTip = "Refresh the picture: the other Mac makes Sill's hidden displays again (for a picture that stays black or wrong)."
            refreshItem = item
            showRefresh()
            return item
        case Self.launcher:
            let item = button(id, "square.grid.3x3", "Show All Apps and Windows", #selector(launcherPressed))
            item.toolTip = "The launcher: every app, window and Desktop of the other Mac"
            return item
        default:
            return nil
        }
    }

    private func button(_ id: NSToolbarItem.Identifier, _ symbol: String, _ label: String, _ action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.toolTip = label
        item.isBordered = true
        item.target = self
        item.action = action
        return item
    }

    private func menuItem(_ id: NSToolbarItem.Identifier, _ symbol: String, _ label: String, _ menu: NSMenu) -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: id)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.toolTip = label
        item.showsIndicator = false
        item.menu = menu
        return item
    }

    // MARK: State

    /// The ⌘ button's look and the refresh button's presence, as they are now.
    @objc func update() {
        guard let window else { return }
        let on = window.capturesShortcuts
        keysButton.state = on ? .on : .off
        keysButton.contentTintColor = on ? .controlAccentColor : nil
        keysButton.title = on ? "Keys to \(client.macName)" : ""
        keysButton.toolTip = on
            ? "⌘Tab, ⌘Space and the other shortcuts go to \(client.macName) while this window has the keyboard. Click to keep them on this Mac."
            : "Send ⌘Tab, ⌘Space and the other shortcuts macOS keeps to \(client.macName) while this window has the keyboard"
        showRefresh()
    }

    /// The refresh button only where the other Mac has hidden displays (greyed out before macOS 15).
    private func showRefresh() {
        guard let refreshItem else { return }
        if #available(macOS 15, *) { refreshItem.isHidden = !client.hostRebuildDesk } else { refreshItem.isEnabled = client.hostRebuildDesk }
    }

    @objc private func keysPressed() { toggleKeys() }

    /// The ⌘ button: this window's capture on or off (Accessibility asked for the first time it is on).
    func toggleKeys() {
        guard let window else { return }
        window.capturesShortcuts.toggle()
        if window.capturesShortcuts, !AppDelegate.agent { _ = SystemKeyTap.trusted(prompt: true) }   // never in a harness run
        SystemKeyTap.shared.refresh()
        update()
    }

    #if DEBUG
    /// The harness: the ⌘ button's title, and a button pressed by name (keys, launcher, refresh).
    var keysTitleForTest: String { keysButton.title }
    func pressForTest(_ name: String) -> Bool {
        switch name {
        case "keys": toggleKeys()
        case "launcher": onLauncher?()
        case "refresh": onRefresh?()
        default: return false
        }
        return true
    }
    #endif

    @objc private func refreshPressed() { onRefresh?() }
    @objc private func launcherPressed() { onLauncher?() }

    // MARK: Menus

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if menu === gestureMenu {
            let gestures: [(String, TrackpadGestures.Gesture, Int)] = [
                ("Mission Control", .swipeUp, 3), ("App Exposé", .swipeDown, 3), ("Previous Space", .swipeRight, 3),
                ("Next Space", .swipeLeft, 3), ("Show Desktop", .spread, 4), ("Show Apps", .pinch, 4),
            ]
            for (title, gesture, fingers) in gestures {
                menu.addItem(ToolbarMenuItem(title) { [client] in _ = client.sendGesture(gesture, fingers: fingers) })
            }
            return
        }
        guard let s = client.settings.displayed else {
            let item = NSMenuItem(title: "Not read yet", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }
        menu.addItem(.sectionHeader(title: "Quality"))
        for q in QualityPreset.allCases {
            menu.addItem(ToolbarMenuItem("\(q.name) — \(q.rawValue / 1_000_000) Mbps", on: s.bitrate == q.rawValue) { [client] in
                client.changeSettings(HostSettingsChange(bitrate: q.rawValue))
            })
        }
        menu.addItem(.sectionHeader(title: "Resolution"))
        for c in SettingsChoices.captureScale {
            menu.addItem(ToolbarMenuItem(LauncherView.scaleName(c), on: s.captureScale == c) { [client] in
                client.changeSettings(HostSettingsChange(captureScale: c))
            })
        }
        menu.addItem(.sectionHeader(title: "Frame Rate"))
        for f in SettingsChoices.maxFPS {
            menu.addItem(ToolbarMenuItem("Up to \(f) fps", on: s.maxFPS == f) { [client] in
                client.changeSettings(HostSettingsChange(maxFPS: f))
            })
        }
    }
}

/// A menu item that runs a closure.
private final class ToolbarMenuItem: NSMenuItem {
    private let run: () -> Void
    init(_ title: String, on: Bool = false, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = on ? .on : .off
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
}
