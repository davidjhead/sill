import AppKit
import SwiftUI
import StreamProtocol

/// The launcher: on connecting, and on a click on Sill Viewer's Dock icon (or opening it again from Finder)
/// while a session is up, it brings forward a window of everything the other Mac offers to open (LauncherView): its Desktops,
/// its open windows, every app and its settings.
///
/// An ordinary window, titled with the other Mac's name and the link's state (shown in its sidebar: the
/// title bar is see-through over the launcher's backdrop), resizable, remembering its frame. It stays open after a choice (the stream's window opens in front of it), and closes with its
/// close button, Command-W, Escape, Disconnect or the session's end. Main thread.
final class Launcher: NSObject, NSWindowDelegate {
    private unowned let app: AppDelegate
    private var window: NSWindow?

    init(app: AppDelegate) { self.app = app }

    var isShown: Bool { window?.isVisible == true }
    /// Add a Mac's page, shown over either state (WelcomeView, the switcher's Add a Mac…).
    let connectPage = ConnectPage()

    /// What the window shows: the welcome page before a session, Add a Mac, or the launcher.
    var page: String {
        connectPage.showsAddMac(app.client) ? "addMac" : app.client.connected ? "launcher" : "welcome"
    }

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        let window = LauncherWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 660),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                    backing: .buffered, defer: false)
        window.title = app.client.connected ? app.client.macName : "Sill Viewer"   // for the Window menu and Mission Control
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = Self.appearance(LauncherTheme.named(UserDefaults.standard.string(forKey: LauncherTheme.key)))
        window.contentMinSize = NSSize(width: 640, height: 440)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.onCancel = { [weak self] in self?.hide() }
        let content = FirstClickHostingView(rootView: LiveLauncher(client: app.client, connectPage: connectPage, launcher: self))
        content.sizingOptions = []   // the window keeps the size it is given (contentMinSize), whatever the page shows
        window.contentView = content
        window.center()
        window.setFrameAutosaveName("SillLauncher")   // after center(): a saved frame wins
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()   // in front of other apps' windows too, though activation is only a request
    }

    func hide() { window?.close() }

    /// The window's own appearance (its menus, title bar buttons, switches) as the theme's.
    static func appearance(_ theme: LauncherTheme) -> NSAppearance? {
        NSAppearance(named: theme.scheme == .dark ? .darkAqua : .aqua)
    }

    fileprivate func themeChanged(_ theme: LauncherTheme) { window?.appearance = Self.appearance(theme) }

    /// Another window in front (a Desktop's or an app's just opened): the search lets go of the
    /// keyboard. Kept, macOS's AutoFill showed its suggestions popover (SafariPlatformSupport's
    /// SPRoundedWindow) under it, empty, over the window now in front, until a click somewhere.
    func windowDidResignKey(_ notification: Notification) {
        window?.makeFirstResponder(nil)
    }

    /// In front again: the search takes the keyboard back (LauncherView).
    func windowDidBecomeKey(_ notification: Notification) {
        NotificationCenter.default.post(name: Self.focusSearch, object: nil)
    }

    static let focusSearch = Notification.Name("SillLauncherFocusSearch")

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil   // a fresh one next time, its search empty
    }

    /// The title bar follows the session: the other Mac's name, and the link's state under it.
    fileprivate func setTitle(_ title: String, subtitle: String) {
        window?.title = title
        window?.subtitle = subtitle
    }

    // MARK: What its buttons do (as the status item's menu does them)

    fileprivate var actions: LauncherActions {
        LauncherActions(
            open: { [weak self] choice in
                guard let self else { return }
                switch choice {
                case .desktop(let source):
                    LauncherMemory.shared.used(LauncherModel.recentKey(source))   // Recent
                    self.app.windows.open(source)
                case .window(let id): self.app.windows.open(.window(id))
                case .app(let bundleID):
                    LauncherMemory.shared.used(bundleID)
                    self.app.windows.openApp(bundleID)   // its windows if it runs there, else a launch
                }
            },
            close: { [weak self] in self?.hide() },
            toggleFavourite: { LauncherMemory.shared.toggleFavourite($0) },
            setAppOrder: { LauncherMemory.shared.appOrder = $0 },
            setQuality: { [weak self] in self?.app.client.changeSettings(HostSettingsChange(bitrate: $0)) },
            setMaxFPS: { [weak self] in self?.app.client.changeSettings(HostSettingsChange(maxFPS: $0)) },
            setCaptureScale: { [weak self] in self?.app.client.changeSettings(HostSettingsChange(captureScale: $0)) },
            applySettings: { [weak self] in self?.app.client.changeSettings($0) },
            setSendAudio: { [weak self] in self?.app.client.changeSettings(HostSettingsChange(sendAudio: $0)) },
            toggleMute: { [weak self] in self?.app.toggleMute() },
            toggleCapture: { SystemKeyTap.shared.enabled.toggle() },
            disconnect: { [weak self] in self?.app.disconnect() },   // the window stays, on the welcome page
            switchMac: { [weak self] id in
                guard let self, let mac = self.app.client.macs.first(where: { $0.id == id }) else { return }
                self.app.client.connect(to: mac)
            },
            addMac: { [weak self] in
                guard let self else { return }
                self.connectPage.startAdding(self.app.client)
            },
            searchNearby: { [weak self] in self?.app.client.searchNearby() })
    }

    /// Whether a listed Mac is the session's: by its saved ID, else by its name.
    static func isCurrent(_ mac: FoundMac, _ client: StreamClient) -> Bool {
        if let id = mac.macID, let current = client.session?.macID { return id == current }
        return mac.name == client.macName
    }

    /// The sidebar's line under the Mac's name: the lock first, else the frame rate while a stream runs.
    static func status(_ client: StreamClient) -> String {
        switch client.lockView ? nil : client.lockWhy {
        case .screenLocked: return "Screen locked"
        case .otherUser: return "Another user is on it"
        case nil: return "Connected" + (client.linkStats.flatMap { $0.fps > 0 ? " · \($0.fps) fps" : nil } ?? "")
        }
    }

    /// What the launcher shows of the session, as LauncherModel reads it (the agent harness reads it too).
    var input: LauncherModel.Input {
        let client = app.client, memory = LauncherMemory.shared
        return LauncherModel.Input(windows: client.orderedWindows, apps: client.apps,
                                   hostDisplays: client.hostDisplays,
                                   desktopNames: client.hostDesktopDisplayNames,
                                   desktopCurrent: client.hostDesktopDisplay,
                                   open: app.windows.openSources,
                                   favourites: memory.favourites, recents: memory.recents,
                                   appOrder: memory.appOrder)
    }

    // MARK: The menu bar menu's Favourites and Recent (StatusMenu)

    /// The favourites as menu items, in the order added, each opening its app as the launcher does (its
    /// windows on the other Mac, else a launch). Adding or removing one is the launcher's right-click.
    func favouriteMenuItems() -> [NSMenuItem] {
        let model = LauncherModel.make(input)
        guard !model.favourites.isEmpty else {
            return [Self.note("No favourites yet: right-click an app in the launcher")]
        }
        return model.favourites.map { appItem($0) }
    }

    /// Recent as menu items: the apps used and the Desktops opened from here, latest first, whichever
    /// order the launcher's All Apps shows.
    func recentMenuItems() -> [NSMenuItem] {
        var recent = input
        recent.appOrder = .recent
        let items = LauncherModel.make(recent).recent
        guard !items.isEmpty else { return [Self.note("Nothing opened from here yet")] }
        return items.map { item in
            switch item {
            case .app(let a): return appItem(a)
            case .desktop(let d):
                let menuItem = ClosureItem(title: d.name == "Desktop" ? "Desktop" : "Desktop — \(d.name)") { [weak self] in
                    self?.actions.open(.desktop(d.source))
                }
                menuItem.image = NSImage(systemSymbolName: "menubar.dock.rectangle", accessibilityDescription: nil)
                menuItem.state = d.isOpen ? .on : .off
                return menuItem
            }
        }
    }

    private func appItem(_ a: LauncherModel.App) -> NSMenuItem {
        let item = ClosureItem(title: a.name) { [weak self] in self?.actions.open(.app(a.bundleID)) }
        if let icon = app.client.icons[a.bundleID]?.copy() as? NSImage {
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        item.state = a.running ? .on : .off
        return item
    }

    private static func note(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    #if DEBUG
    var windowForTest: NSWindow? { window }
    var actionsForTest: LauncherActions { actions }
    #endif
}

/// The launcher's view fed from the session: it redraws as the other Mac's lists, icons, pictures and
/// settings change, and after a switch of this Mac's own (Sound, Shortcuts), which nothing publishes.
private struct LiveLauncher: View {
    @ObservedObject var client: StreamClient
    @ObservedObject var memory = LauncherMemory.shared
    @ObservedObject var connectPage: ConnectPage
    let launcher: Launcher
    @State private var ownSwitches = 0
    /// The status line, drawn apart from the page (LauncherView's ==).
    @StateObject private var liveStatus = LauncherStatus()
    @AppStorage(LauncherTheme.key) private var themeID = LauncherTheme.midnight.id.rawValue

    var body: some View {
        let theme = LauncherTheme.named(themeID)
        Group {
            if client.connected && !launcher.connectPage.showsAddMac(client) {
                launcherView
            } else {
                WelcomeView(client: client, page: launcher.connectPage)
                    .onAppear { launcher.setTitle("Sill Viewer", subtitle: "") }
            }
        }
        .environment(\.launcherTheme, theme)
        .onChange(of: themeID) { launcher.themeChanged(theme) }
    }

    private var launcherView: some View {
        let _ = ownSwitches
        let page = LauncherPage(
            macName: client.macName,
            status: Launcher.status(client),
            input: launcher.input,
            icons: client.icons,
            thumbnails: client.thumbnails,
            settings: LauncherPage.Settings(bitrate: client.settings.displayed?.bitrate,
                                            maxFPS: client.settings.displayed?.maxFPS,
                                            captureScale: client.settings.displayed?.captureScale,
                                            sendAudio: client.settings.displayed?.sendAudio, muted: AudioPlayer.muted,
                                            captureOn: SystemKeyTap.shared.enabled),
            locked: client.lockView ? nil : client.lockWhy,
            macs: client.macs.map { LauncherPage.MacRow(id: $0.id, name: $0.name, word: $0.word, current: Launcher.isCurrent($0, client)) },
            showsNearby: client.showsNearbyHint && !client.searchingNearby,
            linkWarning: LinkWarning.callout(client))
        var actions = launcher.actions
        let mute = actions.toggleMute, capture = actions.toggleCapture
        actions.toggleMute = { mute(); ownSwitches += 1 }
        actions.toggleCapture = { capture(); ownSwitches += 1 }
        return LauncherView(page: page, actions: actions, liveStatus: liveStatus).equatable()
            .onAppear {
                liveStatus.text = page.status
                launcher.setTitle(page.macName, subtitle: page.status)
            }
            .onChange(of: page.macName + "\n" + page.status) {
                liveStatus.text = page.status
                launcher.setTitle(page.macName, subtitle: page.status)
            }
    }
}

/// The launcher's view takes the first click while its window is behind another app's: a click on an app
/// opens it at once, as Launchpad's does, rather than only bringing the window forward.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// The launcher's window: Escape closes it, as Command-W does.
private final class LauncherWindow: NSWindow {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
