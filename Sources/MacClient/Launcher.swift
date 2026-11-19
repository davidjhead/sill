import AppKit
import SwiftUI
import StreamProtocol

/// The launcher: on connecting, and on a click on Sill Viewer's Dock icon (or opening it again from Finder)
/// while a session is up, it brings forward a window of everything the other Mac offers to open (LauncherView): its Desktops,
/// its open windows, every app and its settings.
///
/// An ordinary window, titled with the other Mac's name and the link's state, resizable, remembering its
/// frame. It stays open after a choice (the stream's window opens in front of it), and closes with its
/// close button, Command-W, Escape, Disconnect or the session's end. Main thread.
final class Launcher: NSObject, NSWindowDelegate {
    private unowned let app: AppDelegate
    private var window: NSWindow?

    init(app: AppDelegate) { self.app = app }

    var isShown: Bool { window?.isVisible == true }

    func show() {
        guard app.client.connected else { return }
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        let window = LauncherWindow(contentRect: NSRect(x: 0, y: 0, width: 920, height: 660),
                                    styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                    backing: .buffered, defer: false)
        window.title = app.client.macName
        window.contentMinSize = NSSize(width: 600, height: 440)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.onCancel = { [weak self] in self?.hide() }
        window.contentView = NSHostingView(rootView: LiveLauncher(client: app.client, launcher: self))
        window.center()
        window.setFrameAutosaveName("SillLauncher")   // after center(): a saved frame wins
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()   // in front of other apps' windows too, though activation is only a request
    }

    func hide() { window?.close() }

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
                case .desktop(let source): self.app.windows.open(source)
                case .window(let id): self.app.windows.open(.window(id))
                case .app(let bundleID): self.app.client.launch(bundleID: bundleID)
                }
            },
            close: { [weak self] in self?.hide() },
            setQuality: { [weak self] in self?.app.client.changeSettings(HostSettingsChange(bitrate: $0)) },
            setMaxFPS: { [weak self] in self?.app.client.changeSettings(HostSettingsChange(maxFPS: $0)) },
            toggleSound: { [weak self] in
                guard let self else { return }
                AudioPlayer.enabled.toggle()
                if !AudioPlayer.enabled { self.app.audio.stop() }
                self.app.windows.requestSideStreams()   // the host taps, or gives the apps their sound back
            },
            toggleCapture: { SystemKeyTap.shared.enabled.toggle() },
            disconnect: { [weak self] in
                self?.hide()
                self?.app.disconnect()
            })
    }

    fileprivate var openSources: Set<StreamSource> { app.windows.openSources }
}

/// The launcher's view fed from the session: it redraws as the other Mac's lists, icons, pictures and
/// settings change, and after a switch of this Mac's own (Sound, Shortcuts), which nothing publishes.
private struct LiveLauncher: View {
    @ObservedObject var client: StreamClient
    let launcher: Launcher
    @State private var ownSwitches = 0

    var body: some View {
        let _ = ownSwitches
        let page = LauncherPage(
            macName: client.macName,
            status: "Connected" + (client.linkStats.map { " · \($0.fps) fps" } ?? ""),
            input: LauncherModel.Input(windows: client.orderedWindows, apps: client.apps,
                                       hostDisplays: client.hostDisplays,
                                       desktopNames: client.hostDesktopDisplayNames,
                                       desktopCurrent: client.hostDesktopDisplay,
                                       open: launcher.openSources),
            icons: client.icons,
            thumbnails: client.thumbnails,
            settings: LauncherPage.Settings(bitrate: client.settings.displayed?.bitrate,
                                            maxFPS: client.settings.displayed?.maxFPS,
                                            soundOn: AudioPlayer.enabled, soundAvailable: client.hostAudio,
                                            captureOn: SystemKeyTap.shared.enabled))
        var actions = launcher.actions
        let sound = actions.toggleSound, capture = actions.toggleCapture
        actions.toggleSound = { sound(); ownSwitches += 1 }
        actions.toggleCapture = { capture(); ownSwitches += 1 }
        return LauncherView(page: page, actions: actions)
            .onAppear { launcher.setTitle(page.macName, subtitle: page.status) }
            .onChange(of: page.macName + "\n" + page.status) { launcher.setTitle(page.macName, subtitle: page.status) }
            .onChange(of: client.connected) { _, connected in if !connected { launcher.hide() } }
    }
}

/// The launcher's window: Escape closes it, as Command-W does.
private final class LauncherWindow: NSWindow {
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
