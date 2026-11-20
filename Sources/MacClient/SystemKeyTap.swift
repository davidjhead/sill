import AppKit
import ApplicationServices

/// Capture System Shortcuts (the Mac menu's switch, off by default): ⌘Tab, ⌘Space, ⌃→, ⌘⇧3 and the
/// other keys macOS acts on before any app sees them go to the Mac being controlled instead, while
/// the stream has this app's keyboard. A session event tap, as Screen Sharing's own does; it needs
/// this app allowed in System Settings › Privacy & Security › Accessibility, and asks once.
///
/// Each window has its own (`StreamWindow.capturesShortcuts`, its toolbar's ⌘ button, David,
/// 2026-11-20): a new window starts as this switch says, and the switch sets every open window. The tap
/// exists only while a stream view has the keyboard and its window's capture is on, and it lets every
/// event through untouched once either ends, so a key never sticks here. ⌃⌥⌘⎋ always reaches this
/// app (StreamInputView hands the keyboard back with it). Main thread; the tap's callback runs on
/// the main run loop.
final class SystemKeyTap {
    static let shared = SystemKeyTap()

    /// Accessibility is granted in System Settings, outside this app: look again each time the app
    /// comes back to the front, so the tap is there without the stream having to take the keyboard anew.
    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.update()
        }
    }
    static let defaultsKey = "SillClient.captureSystemShortcuts"
    /// Posted when the switch sets every window (their toolbars' buttons follow).
    static let changed = Notification.Name("SillClient.systemKeyTapChanged")

    private weak var view: StreamInputView?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.defaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.defaultsKey)
            if newValue { Self.askForAccess() }
            for case let window as StreamWindow in NSApp.windows { window.capturesShortcuts = newValue }
            NotificationCenter.default.post(name: Self.changed, object: nil)
            update()
        }
    }

    /// Capture turned on without Accessibility: macOS's own alert once for each build, then Sill Viewer's,
    /// which says why it can still be missing with the switch on in System Settings (an ad hoc build is
    /// a new app to macOS each time: the switch there is an earlier build's) and opens the pane. Never in
    /// a harness run. Main thread.
    static func askForAccess() {
        guard !AppDelegate.agent, !trusted(prompt: false) else { return }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let key = "SillClient.askedAccessibilityBuild"
        if UserDefaults.standard.string(forKey: key) != build {
            UserDefaults.standard.set(build, forKey: key)
            _ = trusted(prompt: true)
            return
        }
        let alert = NSAlert()
        alert.messageText = "Sill Viewer needs Accessibility to send ⌘Tab and ⌘Space"
        alert.informativeText = "Turn on Sill Viewer in System Settings › Privacy & Security › Accessibility (Device Control). "
            + "If it is already on, that entry is for an earlier build of Sill Viewer: select it, remove it with −, "
            + "and add this copy again. Until then, ⌘Tab and ⌘Space stay on this Mac; every other key still goes across."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let pane = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(pane)
    }

    /// Whether this app may tap the keyboard. With `prompt`, macOS shows its alert the first time.
    static func trusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func attach(_ view: StreamInputView) {
        self.view = view
        update()
    }

    func detach(_ view: StreamInputView) {
        guard self.view === view else { return }
        self.view = nil
        update()
    }

    /// A window's ⌘ button changed: the tap follows at once.
    func refresh() { update() }

    /// Whether the window with the keyboard captures: its own setting, or the switch for a view in no
    /// stream window.
    private var wanted: Bool {
        guard let view else { return false }
        return (view.window as? StreamWindow)?.capturesShortcuts ?? enabled
    }

    private func update() {
        let trusted = Self.trusted(prompt: false)
        if wanted, trusted { install() } else { remove() }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "SillKeyLog") {
            FileHandle.standardError.write(Data("keys: capture \(wanted ? "on" : "off"), view \(view != nil), trusted \(trusted), tap \(tap != nil)\n".utf8))
        }
        #endif
    }

    private func install() {
        guard tap == nil else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<SystemKeyTap>.fromOpaque(info).takeUnretainedValue()
            return me.handle(type, event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: CGEventMask(mask), callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            print("system shortcuts: no event tap (Accessibility not allowed)")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        self.source = source
    }

    private func remove() {
        if let port = tap { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard wanted, let view, view.window?.isKeyWindow == true, view.window?.firstResponder === view,
              let ns = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
        let flags = ns.modifierFlags
        // ⌃⌥⌘⎋ is this app's: let it through to the view's monitor.
        if ns.type == .keyDown, ns.keyCode == 53,
           flags.intersection([.control, .option, .command]) == [.control, .option, .command] {
            return Unmanaged.passUnretained(event)
        }
        view.forward(ns.type, keyCode: ns.keyCode, flags: flags, isRepeat: ns.type == .keyDown && ns.isARepeat, via: "tap")
        return nil
    }
}
