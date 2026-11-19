import AppKit
import SwiftUI
import StreamProtocol

/// The launcher: a click on Sill Viewer's Dock icon (or opening it again from Finder) while a session is
/// up covers this Mac's screen with everything the other Mac offers to open (LauncherView): its Desktops,
/// its open windows, every app and its settings, as Launchpad covers it with this Mac's apps.
///
/// One borderless panel over the screen under the pointer, above the menu bar, on a blurred and dimmed
/// backdrop. It closes on Escape, a click outside the tiles, a choice (which then opens, as the status
/// item's menu opens it), the app going to the background, or the session's end. Main thread.
final class Launcher: NSObject, NSWindowDelegate {
    private unowned let app: AppDelegate
    private var panel: LauncherPanel?

    init(app: AppDelegate) { self.app = app }

    var isShown: Bool { panel?.isVisible == true }

    func toggle() { isShown ? hide() : show() }

    func show() {
        guard app.client.connected, !isShown else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        let panel = LauncherPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.hide() }

        let backdrop = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        backdrop.material = .fullScreenUI
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.appearance = NSAppearance(named: .darkAqua)
        backdrop.autoresizingMask = [.width, .height]
        let dim = NSView(frame: backdrop.bounds)
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        dim.autoresizingMask = [.width, .height]
        backdrop.addSubview(dim)
        let content = NSHostingView(rootView: LiveLauncher(client: app.client, launcher: self))
        content.frame = backdrop.bounds
        content.autoresizingMask = [.width, .height]
        backdrop.addSubview(content)
        panel.contentView = backdrop

        self.panel = panel
        panel.alphaValue = 0
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        panel.delegate = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.12; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.orderOut(nil) })
    }

    /// Another app in front, or a window of this one taking the keyboard: the launcher goes, as Launchpad does.
    func windowDidResignKey(_ notification: Notification) { hide() }

    // MARK: What its buttons do (as the status item's menu does them)

    fileprivate var actions: LauncherActions {
        LauncherActions(
            open: { [weak self] choice in
                guard let self else { return }
                self.hide()
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
            .onChange(of: client.connected) { _, connected in if !connected { launcher.hide() } }
    }
}

/// A borderless panel that takes the keyboard (for the search) and closes on Escape.
private final class LauncherPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
