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
                    self.app.client.launch(bundleID: bundleID)
                }
            },
            close: { [weak self] in self?.hide() },
            toggleFavourite: { LauncherMemory.shared.toggleFavourite($0) },
            setAppOrder: { LauncherMemory.shared.appOrder = $0 },
            setQuality: { [weak self] in self?.app.client.changeSettings(HostSettingsChange(bitrate: $0)) },
            setMaxFPS: { [weak self] in self?.app.client.changeSettings(HostSettingsChange(maxFPS: $0)) },
            toggleSound: { [weak self] in
                guard let self else { return }
                AudioPlayer.enabled.toggle()
                if !AudioPlayer.enabled { self.app.audio.stop() }
                self.app.windows.requestSideStreams()   // the host taps, or gives the apps their sound back
            },
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
                                            soundOn: AudioPlayer.enabled, soundAvailable: client.hostAudio,
                                            captureOn: SystemKeyTap.shared.enabled),
            locked: client.lockView ? nil : client.lockWhy,
            macs: client.macs.map { LauncherPage.MacRow(id: $0.id, name: $0.name, word: $0.word, current: Launcher.isCurrent($0, client)) },
            showsNearby: client.showsNearbyHint && !client.searchingNearby)
        var actions = launcher.actions
        let sound = actions.toggleSound, capture = actions.toggleCapture
        actions.toggleSound = { sound(); ownSwitches += 1 }
        actions.toggleCapture = { capture(); ownSwitches += 1 }
        return LauncherView(page: page, actions: actions)
            .onAppear { launcher.setTitle(page.macName, subtitle: page.status) }
            .onChange(of: page.macName + "\n" + page.status) { launcher.setTitle(page.macName, subtitle: page.status) }
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
