#if DEBUG
import AppKit
import StreamProtocol

/// DEBUG `-SillAgent <folder>`, with `-SillConnect` to a test host on this Mac's loopback: an agent
/// drives Sill Viewer's own windows, headless, through files in that folder (Scripts/viewer_agent.py).
/// Each command is a file `<n>.cmd` holding one line; the answer is `<n>.json` beside it, written once
/// the command has run. Nothing else listens: no socket, no port.
///
/// While it runs, no window of the app shows (each is see-through and lets clicks through to what is
/// under it), the app takes no focus and has no Dock icon or status item, and it reaches only a host on
/// 127.0.0.1 or ::1 (`-SillConnect`), never one named by Bonjour or a saved Mac. Its windows are drawn
/// into PNGs from their own views (`snap`), so no screen recording is asked for.
///
/// Commands (docs/BUILD-AND-RUN.md has them in full):
///   state                 the session, the launcher and its sections, the stream windows
///   tree [launcher|key]   a window's accessibility tree: role, label, value, frame
///   click|rightclick|hover <x> <y> [window]   at points from the window's top-left, as `snap` draws it;
///                         a right-click answers with its menu's items, then `choose <item>` or `key esc`
///   choose <item>         an item of the menu a right-click opened
///   scroll <x> <y> <dy>   a scroll there, dy points (positive: down)
///   press <label>         an AppKit-backed control by its accessibility label (SwiftUI's own are not reached)
///   type <text>           text into the focused field
///   key <keys>            a key or a shortcut: esc, return, tab, ctrl-cmd-s, cmd-w…
///   launcher show|hide
///   snap <path> [launcher|key|all]
///   wait <what> [seconds] connected | apps | windows | launcher | stream | sendaudio (the other Mac's
///                         Send Audio on) | sound (its sound decoded here) | standard | retina
///                         (its Resolution) (default 10 s)
///   dockicon <path>       the Desktop's Dock icon as a PNG
///   toolbar keys|launcher|refresh [window]   a stream window's toolbar button
///   capture on|off        the launcher's Capture shortcuts switch, for every window
///   linkwarning behind|clear   the other Mac's link report faked: can't carry Extreme, or keeping up
///   statusmenu favourites|recent <title>   an item of the menu bar menu's Favourites or Recent chosen
///   fakemacs              sample Mac rows for the welcome page and the switcher
///   quit
enum AgentHarness {
    private static var folder: URL?
    private static var timer: Timer?
    private static weak var app: AppDelegate?
    private static var seen = Set<String>()
    private static var openMenu: NSMenu?

    /// Whether this run is the harness's: read once, at launch, before any window.
    static let enabled: Bool = UserDefaults.standard.string(forKey: "SillAgent") != nil

    static func start(_ app: AppDelegate) {
        guard let path = UserDefaults.standard.string(forKey: "SillAgent") else { return }
        let address = UserDefaults.standard.string(forKey: "SillConnect") ?? ""
        let host = address.hasPrefix("[") ? String(address.dropFirst().prefix { $0 != "]" }) : String(address.split(separator: ":").first ?? "")
        guard ["127.0.0.1", "::1", "localhost"].contains(host) else {
            FileHandle.standardError.write(Data("agent: refused: -SillAgent needs -SillConnect to a test host on this Mac's loopback\n".utf8))
            exit(2)
        }
        self.app = app
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folder = url
        NSApp.setActivationPolicy(.prohibited)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in tick() }
        RunLoop.main.add(timer!, forMode: .common)
        try? Data("ready\n".utf8).write(to: url.appendingPathComponent("ready"))
        FileHandle.standardError.write(Data("agent: listening in \(path)\n".utf8))
    }

    private static func tick() {
        for w in NSApp.windows where w.alphaValue != 0 || !w.ignoresMouseEvents {
            w.alphaValue = 0
            w.ignoresMouseEvents = true
        }
        guard let folder, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names.sorted() where name.hasSuffix(".cmd") && !seen.contains(name) {
            seen.insert(name)
            let url = folder.appendingPathComponent(name)
            let line = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let reply = folder.appendingPathComponent(String(name.dropLast(4)) + ".json")
            run(line) { answer in
                let data = (try? JSONSerialization.data(withJSONObject: answer, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
                let tmp = reply.appendingPathExtension("tmp")
                try? data.write(to: tmp)
                try? FileManager.default.moveItem(at: tmp, to: reply)
            }
        }
    }

    // MARK: Commands

    private static func run(_ line: String, _ done: @escaping ([String: Any]) -> Void) {
        guard let app else { return done(["ok": false, "error": "no app"]) }
        let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        let rest = words.dropFirst().joined(separator: " ")
        func ok(_ more: [String: Any] = [:]) { done(more.merging(["ok": true]) { a, _ in a }) }
        func fail(_ why: String) { done(["ok": false, "error": why]) }
        switch words.first ?? "" {
        case "state":
            ok(state(app))
        case "tree":
            guard let window = window(words.dropFirst().first ?? "launcher", app) else { return fail("no such window") }
            ok(["tree": node(window.contentView as Any, in: window, depth: 0) ?? [:]])
        case "press":
            guard let (element, _) = find(rest, app) else { return fail("nothing labelled “\(rest)”") }
            if perform(element, .press) { return settle { ok() } }
            fail("“\(rest)” does not press")
        case "click", "rightclick", "hover":
            // x y in points from the window's top-left, as `snap` draws it.
            guard words.count >= 3, let x = Double(words[1]), let y = Double(words[2]) else { return fail("\(words[0]) <x> <y> [window]") }
            guard let w = window(words.count > 3 ? words[3] : "launcher", app) else { return fail("no such window") }
            // The layout brought up to date first: a click right after a change (a favourite added, a
            // pane chosen) would land where things were before SwiftUI laid them out again.
            w.contentView?.layoutSubtreeIfNeeded()
            w.displayIfNeeded()
            let at = NSPoint(x: x, y: w.frame.height - y)
            mouse(w, .mouseMoved, at)
            if words[0] == "hover" { return settle { ok() } }
            // A click or a right-click may open a menu (a right-click's, a pop-up button's), whose tracking
            // holds the main thread until it closes: the answer (the menu's items) goes from inside it, and
            // `choose` picks one, or `key esc` closes it.
            let right = words[0] == "rightclick"
            // The answer goes from the menu's own notification, inside its tracking (the main queue may not
            // run there); with no menu after the events, from here.
            openMenu = nil
            var answered = false
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
                guard !answered, let menu = note.object as? NSMenu else { return }
                answered = true
                openMenu = menu
                if let observer { NotificationCenter.default.removeObserver(observer) }
                ok(["menu": menu.items.map { $0.isSeparatorItem ? "—" : $0.title }])
            }
            DispatchQueue.main.async {
                if right { mouse(w, .rightMouseDown, at); mouse(w, .rightMouseUp, at) } else { mouse(w, .leftMouseDown, at); mouse(w, .leftMouseUp, at) }
                DispatchQueue.main.asyncAfter(deadline: .now() + (right ? 0.5 : 0.35)) {
                    guard !answered else { return }
                    answered = true
                    if let observer { NotificationCenter.default.removeObserver(observer) }
                    if right { fail("no menu opened at \(Int(x)), \(Int(y))") } else { ok() }
                }
            }
        case "choose":
            // The item by its title, else the first whose title starts so ("choose Disconnect").
            guard let menu = openMenu,
                  let i = menu.items.firstIndex(where: { $0.title.caseInsensitiveCompare(rest) == .orderedSame })
                      ?? menu.items.firstIndex(where: { $0.title.lowercased().hasPrefix(rest.lowercased()) }) else {
                return fail("no open menu has “\(rest)”")
            }
            openMenu = nil
            menu.cancelTracking()
            DispatchQueue.main.async { menu.performActionForItem(at: i) }
            // The item's action runs once the menu has closed, and what it changes is laid out after:
            // longer than a click's settle.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                NSApp.windows.forEach { $0.contentView?.layoutSubtreeIfNeeded() }
                ok()
            }
        case "scroll":
            // scroll <x> <y> <dy>: dy points down (positive) or up, as a trackpad's scroll.
            guard words.count >= 4, let x = Double(words[1]), let y = Double(words[2]), let dy = Double(words[3]),
                  let w = window("launcher", app) else { return fail("scroll <x> <y> <dy>") }
            if let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(-dy), wheel2: 0, wheel3: 0),
               let ns = NSEvent(cgEvent: e) {
                _ = ns
                let at = NSPoint(x: x, y: w.frame.height - y)
                e.location = CGPoint(x: w.frame.minX + at.x, y: (NSScreen.screens.first?.frame.height ?? 0) - (w.frame.minY + at.y))
                if let moved = NSEvent(cgEvent: e) { w.sendEvent(moved) }
            }
            settle { ok() }
        case "type":
            guard let window = keyWindow(app), let responder = (window.firstResponder as? NSTextView) ?? (window.fieldEditor(false, for: nil) as? NSTextView) else {
                return fail("no focused field")
            }
            responder.insertText(rest, replacementRange: NSRange(location: NSNotFound, length: 0))   // at the selection
            settle { ok() }
        case "key":
            if rest == "esc", let menu = openMenu { openMenu = nil; menu.cancelTracking(); return settle { ok() } }
            guard let event = keyEvent(rest) else { return fail("unknown key “\(rest)”") }
            guard let window = keyWindow(app) else { return fail("no window") }
            if !window.performKeyEquivalent(with: event), !NSApp.mainMenu!.performKeyEquivalent(with: event) {
                window.sendEvent(event)
            }
            settle { ok() }
        case "launcher":
            if words.dropFirst().first == "hide" { app.launcher.hide() } else { app.launcher.show() }
            settle { ok() }
        case "snap":
            guard words.count >= 2 else { return fail("snap <path> [launcher|key|all]") }
            let which = words.count > 2 ? words[2] : "launcher"
            let windows = which == "all" ? NSApp.windows.filter(\.isVisible) : [window(which, app)].compactMap { $0 }
            guard !windows.isEmpty else { return fail("no such window") }
            var written: [String] = []
            for (i, w) in windows.enumerated() {
                let path = windows.count == 1 ? words[1] : words[1].replacingOccurrences(of: ".png", with: "-\(i).png")
                if snap(w, to: path) { written.append(path) }
            }
            ok(["written": written])
        case "wait":
            let what = words.dropFirst().first ?? "connected"
            let limit = Date().addingTimeInterval(Double(words.dropFirst(2).first ?? "") ?? 10)
            func poll() {
                if met(what, app) { return ok(state(app)) }
                if Date() > limit { return done(["ok": false, "error": "not \(what) in time"].merging(state(app)) { a, _ in a }) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: poll)
            }
            poll()
        case "toolbar":
            // toolbar keys|launcher|refresh [window]: a stream window's toolbar button pressed (the
            // frontmost stream window when none is named).
            guard words.count >= 2 else { return fail("toolbar keys|launcher|refresh [window]") }
            let named = words.count > 2 ? words[2...].joined(separator: " ") : nil
            let target = named.flatMap { n in NSApp.windows.first { $0 is StreamWindow && $0.title == n } }
                ?? NSApp.orderedWindows.first { $0 is StreamWindow && $0.isVisible }
            guard let w = target as? StreamWindow, let bar = w.toolbarController else { return fail("no stream window") }
            guard bar.pressForTest(words[1]) else { return fail("no toolbar button “\(words[1])”") }
            settle { ok(state(app)) }
        case "linkwarning":
            // linkwarning behind|clear: the other Mac's link report as though it said the link can't
            // carry Extreme (recommending Low), or keeps up (LinkWarning.testLink).
            if words.dropFirst().first == "behind" {
                LinkWarning.testLink = LinkReport(state: LinkReport.behind, withheldPerSecond: 28, bitrate: QualityPreset.extreme.rawValue,
                                                  carriedKbps: 13_500, suggestedBitrate: QualityPreset.low.rawValue)
            } else {
                LinkWarning.testLink = nil
            }
            app.client.objectWillChange.send()
            app.windows.updateToolbars()
            settle { ok(state(app)) }
        case "capture":
            // capture on|off: the launcher's Capture shortcuts switch (every open window follows).
            SystemKeyTap.shared.enabled = words.dropFirst().first == "on"
            settle { ok(state(app)) }
        case "statusmenu":
            // statusmenu favourites|recent <title>: the menu bar menu's item chosen (a harness run has no
            // status item, so its submenus are built as the menu builds them).
            guard words.count >= 3 else { return fail("statusmenu favourites|recent <title>") }
            let items = words[1] == "recent" ? app.launcher.recentMenuItems() : app.launcher.favouriteMenuItems()
            let title = words[2...].joined(separator: " ")
            guard let item = items.first(where: { $0.title == title }), let action = item.action else { return fail("no item “\(title)”") }
            NSApp.sendAction(action, to: item.target, from: item)
            settle { ok() }
        case "fakemacs":
            // Sample rows for the welcome page and the switcher (the harness never browses): a wired Mac,
            // one on Wi-Fi, a saved one away from home and one not paired. Picking one dials nothing real.
            app.client.macs = [
                FoundMac(name: "Studio", endpoint: nil, route: .network, method: .wired),
                FoundMac(name: "MacBook Air", endpoint: nil, route: .network, method: .wifi),
                FoundMac(name: "Office iMac", endpoint: nil, route: .remote, macID: "agent-office"),
                FoundMac(name: "Mac mini", endpoint: nil, route: .network, homeWord: .notPaired),
            ]
            settle { ok() }
        case "dockicon":
            // dockicon <path>: the Desktop's Dock icon, badged as the Dock shows it, as a PNG.
            guard words.count >= 2 else { return fail("dockicon <path>") }
            let image = DockProxies.badged(DockProxies.desktopIcon)
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]),
                  (try? png.write(to: URL(fileURLWithPath: words[1]))) != nil else { return fail("not written") }
            ok(["written": [words[1]]])
        case "quit":
            ok()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
        default:
            fail("unknown command “\(line)”")
        }
    }

    /// A moment for SwiftUI to redraw after an action, so the next `state` or `snap` sees it.
    private static func settle(_ then: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: then)
    }

    private static func met(_ what: String, _ app: AppDelegate) -> Bool {
        switch what {
        case "connected": app.client.connected
        case "apps": !app.client.apps.isEmpty
        case "windows": !app.client.windows.isEmpty
        case "launcher": app.launcher.isShown
        case "stream": app.client.active != .none
        case "sendaudio": app.client.settings.displayed?.sendAudio == true
        case "sound": app.audio.framesDecoded > 0
        case "standard": app.client.settings.displayed?.captureScale == 1
        case "retina": app.client.settings.displayed?.captureScale == 2
        default: false
        }
    }

    private static func state(_ app: AppDelegate) -> [String: Any] {
        let client = app.client
        let model = LauncherModel.make(app.launcher.input)
        let streams: [[String: Any]] = NSApp.windows.filter { $0.isVisible && $0.delegate === app.windows }.map {
            var info: [String: Any] = ["title": $0.title, "key": $0.isKeyWindow, "frame": rect($0.frame)]
            if let w = $0 as? StreamWindow {
                info["keys"] = w.capturesShortcuts
                info["keysTitle"] = w.toolbarController?.keysTitleForTest ?? ""
                info["toolbar"] = w.toolbar?.items.map(\.itemIdentifier.rawValue) ?? []
            }
            return info
        }
        return [
            "connected": client.connected,
            "macName": client.macName,
            "page": app.launcher.page,
            "theme": UserDefaults.standard.string(forKey: LauncherTheme.key) ?? "midnight",
            "query": LauncherQuery.current,
            "renders": LauncherQuery.renders,
            "macs": client.macs.map(\.name),
            "locked": client.lockWhy.map { "\($0)" } ?? "",
            "macID": client.session?.macID ?? "",
            "active": "\(client.active)",
            "stream": ["bitrate": client.settings.displayed?.bitrate ?? 0, "maxFPS": client.settings.displayed?.maxFPS ?? 0,
                       "resolution": client.settings.displayed.map { LauncherView.scaleName($0.captureScale) } ?? ""],
            "linkWarning": LinkWarning.callout(client).map { ["text": $0.text, "button": $0.button?.title ?? ""] } ?? ["text": "", "button": ""],
            "sound": ["sendAudio": client.settings.displayed?.sendAudio.map { $0 ? "on" : "off" } ?? "none",
                      "muted": AudioPlayer.muted, "frames": app.audio.framesDecoded],
            "counts": ["apps": client.apps.count, "windows": client.windows.count, "icons": client.icons.count],
            "launcher": [
                "shown": app.launcher.isShown,
                "sidebarHidden": UserDefaults.standard.bool(forKey: "launcher.sidebarHidden"),
                "appOrder": app.launcher.input.appOrder.rawValue,
                "desktops": model.desktops.map { ["name": $0.name, "detail": $0.detail ?? "", "open": $0.isOpen] },
                "windows": model.windows.map { ["id": $0.id, "title": $0.title, "app": $0.appName, "open": $0.isOpen] },
                "favourites": model.favourites.map(\.name),
                "apps": model.apps.map(\.name),
                "recent": model.recent.map(\.name),
            ],
            "streamWindows": streams,
            "dock": app.windows.dock.planned,
            "menuFavourites": app.launcher.favouriteMenuItems().map(\.title),
            "menuRecent": app.launcher.recentMenuItems().map(\.title),
            "visibleWindows": NSApp.windows.filter(\.isVisible).map { $0.title.isEmpty ? String(describing: type(of: $0)) : $0.title },
            "allWindows": NSApp.windows.map { "\(type(of: $0)) visible=\($0.isVisible) level=\($0.level.rawValue) \(Int($0.frame.width))x\(Int($0.frame.height)) from \(Bundle(for: type(of: $0)).bundleURL.lastPathComponent)" },
            "firstResponder": app.launcher.windowForTest.map { String(describing: type(of: $0.firstResponder as Any)) } ?? "",
        ]
    }

    // MARK: Windows

    private static func window(_ which: String, _ app: AppDelegate) -> NSWindow? {
        switch which {
        case "launcher": app.launcher.windowForTest
        case "key": keyWindow(app)
        default: NSApp.windows.first { $0.isVisible && $0.title == which }
        }
    }

    /// The app is never active here, so no window is key: the launcher when it shows, else the window
    /// that would be (the frontmost of the app's).
    private static func keyWindow(_ app: AppDelegate) -> NSWindow? {
        NSApp.keyWindow ?? app.launcher.windowForTest ?? NSApp.orderedWindows.first { $0.isVisible }
    }

    private static func snap(_ window: NSWindow, to path: String) -> Bool {
        guard let frame = window.contentView?.superview,
              let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return false }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: URL(fileURLWithPath: path))) != nil
    }

    private static func rect(_ r: NSRect) -> [Int] { [Int(r.minX), Int(r.minY), Int(r.width), Int(r.height)] }

    // MARK: Accessibility

    // SwiftUI builds its accessibility tree for the older, attribute-based API (accessibilityAttributeValue),
    // not for an in-process caller of the newer methods, so the harness reads that one.

    private static func attr(_ element: Any, _ name: NSAccessibility.Attribute) -> Any? {
        (element as? NSObject)?.accessibilityAttributeValue(name)
    }

    private static func children(_ element: Any) -> [Any] {
        (attr(element, .children) as? [Any]) ?? []
    }

    private static func label(_ element: Any) -> String {
        let names: [NSAccessibility.Attribute] = [.description, .title, .value, .help]
        for n in names { if let t = attr(element, n) as? String, !t.isEmpty { return t } }
        return ""
    }

    private static func role(_ element: Any) -> String {
        ((attr(element, .role) as? String) ?? "").replacingOccurrences(of: "AX", with: "")
    }

    private static func perform(_ element: Any, _ action: NSAccessibility.Action) -> Bool {
        guard let e = element as? NSObject, (e.accessibilityActionNames() ).contains(action) else { return false }
        e.accessibilityPerformAction(action)
        return true
    }

    private static func node(_ element: Any, in window: NSWindow, depth: Int) -> [String: Any]? {
        guard depth < 40 else { return nil }
        var out: [String: Any] = [:]
        let r = role(element)
        if !r.isEmpty { out["role"] = r }
        let l = label(element)
        if !l.isEmpty { out["label"] = l }
        if let p = attr(element, .position) as? NSPoint, let z = attr(element, .size) as? NSSize, z != .zero {
            // Screen coordinates, flipped: as the window's top-left sees them.
            let top = (NSScreen.screens.first?.frame.maxY ?? 0)
            out["frame"] = rect(NSRect(x: p.x - window.frame.minX, y: p.y - (top - window.frame.maxY), width: z.width, height: z.height))
        }
        if (attr(element, .enabled) as? Bool) == false { out["disabled"] = true }
        if (attr(element, .selected) as? Bool) == true { out["selected"] = true }
        if let v = attr(element, .value) as? NSNumber, r == "CheckBox" || r == "Switch" { out["on"] = v.boolValue }
        let kids = children(element).compactMap { node($0, in: window, depth: depth + 1) }
        if !kids.isEmpty { out["children"] = kids }
        // Groups with nothing to say and one child are folded into it.
        if out["label"] == nil, kids.count == 1, ["Group", "Unknown", ""].contains(r) { return kids[0] }
        return out
    }

    private static func find(_ wanted: String, _ app: AppDelegate) -> (Any, NSWindow)? {
        let windows = [app.launcher.windowForTest].compactMap { $0 } + NSApp.orderedWindows.filter(\.isVisible)
        let w = wanted.lowercased()
        for exact in [true, false] {
            for window in windows {
                var queue: [Any] = [window.contentView as Any]
                var i = 0
                while i < queue.count && i < 5000 {
                    let e = queue[i]; i += 1
                    let l = label(e).lowercased()
                    if !l.isEmpty, exact ? l == w : l.hasPrefix(w) { return (e, window) }
                    queue += children(e)
                }
            }
        }
        return nil
    }

    /// The element's right-click menu: SwiftUI's context menu, opened through accessibility, then the item
    /// pressed by its title.
    private static func menu(_ element: Any, item: String) -> Bool {
        var found = false
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { note in
            guard let menu = note.object as? NSMenu,
                  let i = menu.items.firstIndex(where: { $0.title.caseInsensitiveCompare(item) == .orderedSame }) else { return }
            found = true
            DispatchQueue.main.async {
                menu.performActionForItem(at: i)
                menu.cancelTracking()
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        _ = perform(element, .showMenu)
        return found
    }

    private static func mouse(_ w: NSWindow, _ type: NSEvent.EventType, _ at: NSPoint) {
        let pressure: Float = (type == .leftMouseDown || type == .rightMouseDown) ? 1 : 0
        guard let e = NSEvent.mouseEvent(with: type, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: pressure) else { return }
        w.sendEvent(e)
    }

    // MARK: Keys

    private static func keyEvent(_ spec: String) -> NSEvent? {
        let parts = spec.lowercased().split(separator: "-").map(String.init)
        guard let key = parts.last else { return nil }
        var flags: NSEvent.ModifierFlags = []
        for m in parts.dropLast() {
            switch m {
            case "cmd": flags.insert(.command)
            case "ctrl": flags.insert(.control)
            case "opt", "alt": flags.insert(.option)
            case "shift": flags.insert(.shift)
            default: return nil
            }
        }
        let named: [String: (UInt16, String)] = ["esc": (53, "\u{1b}"), "return": (36, "\r"), "tab": (48, "\t"),
                                                 "space": (49, " "), "delete": (51, "\u{7f}"),
                                                 "left": (123, "\u{F702}"), "right": (124, "\u{F703}"),
                                                 "down": (125, "\u{F701}"), "up": (126, "\u{F700}")]
        let letters: [String: UInt16] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
                                         "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
                                         "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
                                         "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22]
        let (code, chars): (UInt16, String)
        if let n = named[key] { (code, chars) = n } else if let c = letters[key] { (code, chars) = (c, key) } else { return nil }
        return NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                windowNumber: (NSApp.keyWindow ?? NSApp.windows.first)?.windowNumber ?? 0, context: nil,
                                characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)
    }
}
#endif
