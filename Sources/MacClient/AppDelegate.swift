import AppKit
import Combine
import SwiftUI
import StreamProtocol

/// The app: one StreamClient (the iPhone and iPad app's session, shared), the other Mac's windows as
/// this Mac's windows (StreamWindows), the controlled app's menus in the menu bar (MainMenu), and
/// Sill's own controls in a status item (StatusMenu). The connect window shows while no session is
/// up, and from the status item.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let client = StreamClient()
    private let reporter = ClientStatsReporter()
    private(set) lazy var windows = StreamWindows(client: client)
    private(set) lazy var mainMenu = MainMenu(client: client)
    private var status: StatusMenu?
    private(set) lazy var launcher = Launcher(app: self)
    private var clipboardSync: ClipboardSync?
    let audio = AudioPlayer()
    private var connectWindow: NSWindow?
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        client.picksDesktopItself = false   // the user's windows to open; the Desktop once, on connecting
        #if DEBUG
        AgentHarness.start(self)   // -SillAgent <folder>: an agent drives the app headless (AgentHarness)
        #endif
        reporter.attach(to: client)
        mainMenu.install()
        if !Self.agent { status = StatusMenu(app: self) }
        clipboardSync = ClipboardSync(client: client)
        let audio = self.audio
        client.onAudio = { if AudioPlayer.enabled { audio.receive($0) } }
        client.$connected.removeDuplicates().sink { [weak self] connected in
            DispatchQueue.main.async { self?.connectedChanged(connected) }
        }.store(in: &subscriptions)
        // A Mac without an ID (no identity yet, a test host) is remembered by its name, which comes with
        // its first window list, after the session is up.
        client.$macName.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.client.connected else { return }
                LauncherMemory.shared.use(mac: self.launcherMemoryKey)
            }
        }.store(in: &subscriptions)
        #if DEBUG
        if Self.agent {   // the harness's test host alone: no Bonjour, no saved Macs, no reconnect
            client.connectFromLaunchArgument()
            return
        }
        #endif
        client.startBrowsing()
        client.startRemote()
        #if DEBUG
        client.connectFromLaunchArgument()   // -SillConnect host:port, for the off-Bonjour test hosts
        #endif
        if let last = UserDefaults.standard.string(forKey: Self.lastMacKey), !client.connected, client.reconnectAtLaunch(last) {
            // Back to the Mac it was connected to when it quit, without a window in the way (it may be
            // a launch at login); the connect window only if that has not worked after a while.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.reconnectPatience) { [weak self] in
                guard let self, !self.client.connected else { return }
                self.showConnectWindow()
            }
            return
        }
        if !client.connected { showConnectWindow() }
        NSApp.activate()
    }

    /// The saved Mac (its Mac ID) this app was connected to when it last quit, reconnected to at
    /// launch; forgotten by Disconnect, so a Mac left on purpose stays left.
    private static let lastMacKey = "SillClient.lastMac"

    #if DEBUG
    private static var agent: Bool { AgentHarness.enabled }
    #else
    private static let agent = false
    #endif
    /// How long a launch's reconnect has before the connect window shows (the reconnect itself goes
    /// on, DiscoveryPolicy.redialWindow).
    private static let reconnectPatience: TimeInterval = 15

    func applicationWillTerminate(_ notification: Notification) {
        windows.closeAll()   // keeps the list of open windows for the next session (closeAll does not forget it)
        windows.dock.quitAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// A click on the Dock icon, or opening the app again from Finder: while a session is up, the launcher's
    /// window (everything the other Mac offers to open) comes forward, whatever windows are open; with
    /// none, the connect window when no window shows.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if client.connected {
            launcher.show()
            return false   // the launcher stands for the windows AppKit would otherwise bring forward
        }
        if !flag { showConnectWindow() }
        return true
    }

    /// sill://pair from Messages or a browser: a confirmation first, in the connect window.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { client.handleOpenURL(url) }
        showConnectWindow()
    }

    private func connectedChanged(_ connected: Bool) {
        windows.onRestored = { [weak self] in
            guard let self, self.launcher.isShown else { return }
            Timer.scheduledTimer(withTimeInterval: 0, repeats: false) { [weak self] _ in self?.launcher.show() }
        }
        if connected {
            if let mac = client.session?.macID { UserDefaults.standard.set(mac, forKey: Self.lastMacKey) }
            LauncherMemory.shared.use(mac: launcherMemoryKey)   // the launcher's favourites and recents of this Mac
            connectWindow?.orderOut(nil)
            // The launcher's window comes in front of every other window, so something can be picked
            // from all the other Mac offers (its apps, windows, Desktops and settings); the windows
            // open last time with this Mac come back behind it (StreamWindows), and once they have,
            // it comes in front of them again. From a run-loop timer, as everything this app opens
            // from the session's start (the modal-loop rule).
            Timer.scheduledTimer(withTimeInterval: 0, repeats: false) { [weak self] _ in
                guard let self, self.client.connected else { return }
                self.launcher.show()
            }
            #if DEBUG
            // -SillOpenWindows N: the host's first N windows open unfocused (side streams, nothing
            // resized), once its list has come.
            let n = UserDefaults.standard.integer(forKey: "SillOpenWindows")
            if UserDefaults.standard.bool(forKey: "SillFlipTest") {
                // -SillFlipTest 1: once the windows are back, the focus goes from one open stream
                // window to the next every 3 s, six times, as a person flipping between apps would.
                for i in 0..<6 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8 + Double(i) * 3) { [weak self] in
                        guard let self else { return }
                        let open = self.windows.openSources.sorted { "\($0)" < "\($1)" }
                        guard open.count >= 2 else { FileHandle.standardError.write(Data("flip test: FAIL \(open.count) windows open\n".utf8)); return }
                        self.windows.flipTest(to: open[i % open.count])
                    }
                }
            }
            if UserDefaults.standard.bool(forKey: "SillResizeTest") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.windows.open(.desktop)
                    MacResizeTest.run()
                }
            }
            if n > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self else { return }
                    for w in self.client.windows.prefix(n) { self.windows.open(.window(w.id), focus: false) }
                    print("test: opened \(min(n, self.client.windows.count)) windows unfocused")
                }
            }
            #endif
        } else {
            audio.stop()
            windows.closeAll()
            showConnectWindow()
        }
    }

    /// Whose favourites and recents the launcher shows: the session's Mac by its ID, else by its name.
    private var launcherMemoryKey: String? {
        if let id = client.session?.macID { return id }
        return client.macName.isEmpty ? nil : "name:" + client.macName
    }

    func showConnectWindow() {
        if connectWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ConnectView(client: client)))
            window.title = "Connect to a Mac"
            window.setContentSize(NSSize(width: 560, height: 520))
            window.isReleasedWhenClosed = false
            window.center()
            connectWindow = window
        }
        connectWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.lastMacKey)
        windows.letGo()
        client.disconnect()
    }
}
