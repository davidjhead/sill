import AppKit
import SwiftUI
import StreamProtocol

/// What the launcher shows besides its sections: the other Mac, its icons and window pictures, and its
/// settings as the status item's menu has them. Plain data, so the view renders without a session
/// (LauncherPreview).
struct LauncherPage {
    struct Settings {
        var qualities: [(name: String, bitrate: Int)] = QualityPreset.allCases.map { ($0.name, $0.rawValue) }
        var bitrate: Int?                         // nil: the settings are not read yet
        var maxFPS: Int?
        var fpsChoices: [Int] = SettingsChoices.maxFPS
        var soundOn = false
        var soundAvailable = false
        var captureOn = false
    }

    var macName: String
    var status: String                            // "Connected · 60 fps"
    var input: LauncherModel.Input
    var icons: [String: NSImage] = [:]            // by bundle ID
    var thumbnails: [UInt32: NSImage] = [:]       // by window ID
    var settings = Settings()
    /// Why the other Mac shows nothing of itself (its screen locked, another user on it): its apps,
    /// windows and icons are withheld until it is back, and the launcher says so in their place.
    var locked: LockedMac.Why? = nil
    /// The Macs this one can reach (the network's and the saved ones), for the switcher on the Mac's name.
    var macs: [MacRow] = []
    var showsNearby = false

    struct MacRow: Equatable {
        var id: String          // FoundMac.id
        var name: String
        var word: String?       // Wired, Wi-Fi, Remote, Not paired…
        var current: Bool
    }
}

/// What the launcher's buttons do. The launcher's window stays open after a choice (Launcher).
struct LauncherActions {
    var open: (LauncherModel.Choice) -> Void = { _ in }
    var close: () -> Void = {}
    var toggleFavourite: (String) -> Void = { _ in }
    var setAppOrder: (LauncherModel.AppOrder) -> Void = { _ in }
    var setQuality: (Int) -> Void = { _ in }
    var setMaxFPS: (Int) -> Void = { _ in }
    var toggleSound: () -> Void = {}
    var toggleCapture: () -> Void = {}
    var disconnect: () -> Void = {}
    var switchMac: (String) -> Void = { _ in }   // a MacRow's id
    var addMac: () -> Void = {}
    var searchNearby: () -> Void = {}
}

/// The launcher's page, from the "glass sidebar" design (the Sidebar and Glass options together): dark
/// always, on a blurred backdrop that suggests a wallpaper, with a frosted sidebar floating at the left
/// (the other Mac and its link, Home, Favourites and All Apps, its Desktops, and its settings) and the
/// content beside it in one scroll: the open windows as big pictures, the favourites on a Dock-like
/// shelf, and every app in a grid (a dot under the running ones; A to Z or most recent first; a
/// right-click adds one to the favourites or takes it out).
///
/// The sidebar hides and comes back with the button beside the title or Control-Command-S, remembered
/// for every launcher; while it is hidden the Desktops join the open windows and the settings sit in a
/// capsule at the top right. The window's own title bar is see-through, its buttons over the sidebar.
struct LauncherView: View {
    enum Pane: Hashable { case home, favourites, apps }

    let page: LauncherPage
    let actions: LauncherActions
    @State private var query = ""
    @State private var pane = Pane.home
    @AppStorage("launcher.sidebarHidden") private var sidebarHidden = false
    @FocusState private var searchFocused: Bool

    private var model: LauncherModel { LauncherModel.make(page.input, query: query) }

    var body: some View {
        let model = self.model
        HStack(spacing: 10) {
            if !sidebarHidden {
                sidebar(model)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            content(model)
        }
        .padding(6)   // close enough to the window's corner that its buttons sit inside the sidebar's
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()   // under the see-through title bar: its buttons sit over the sidebar
        .background(Backdrop())
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .onAppear { searchFocused = true }
        .onExitCommand { actions.close() }
    }

    private func toggleSidebar() {
        withAnimation(.spring(duration: 0.3)) { sidebarHidden.toggle() }
    }

    // MARK: Sidebar

    private func sidebar(_ model: LauncherModel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            macHeader.padding(.top, 32).padding(.bottom, 12)
            paneRow(.home, "Home", "house")
            paneRow(.favourites, "Favourites", "star")
            paneRow(.apps, "All Apps", "square.grid.2x2")
            if !model.desktops.isEmpty {
                Text("Desktops").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 9).padding(.top, 14).padding(.bottom, 3)
                ForEach(model.desktops, id: \.name) { d in desktopRow(d) }
            }
            Spacer(minLength: 12)
            sidebarSettings
            Button(action: actions.disconnect) {
                Text("Disconnect").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.71, blue: 0.67))
                    .frame(maxWidth: .infinity).frame(height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain).padding(.top, 4)
        }
        .padding(.horizontal, 10).padding(.bottom, 10)
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(Glass(cornerRadius: 14, fill: 0.10, stroke: 0.16).shadow(color: .black.opacity(0.25), radius: 15, y: 10))
    }

    /// The Mac and its link, and a menu of the other Macs on a click: connect to another, add one,
    /// search nearby, or disconnect (the welcome page is where a session starts; this is for changing it).
    private var macHeader: some View {
        Menu {
            if !page.macs.isEmpty {
                Section("Connect to") {
                    ForEach(page.macs, id: \.id) { m in
                        Button { if !m.current { actions.switchMac(m.id) } } label: {
                            let title = m.name + (m.word.map { " — \($0)" } ?? "")
                            if m.current { Label(title, systemImage: "checkmark") } else { Text(title) }
                        }
                    }
                }
                Divider()
            }
            Button("Add a Mac…", action: actions.addMac)
            if page.showsNearby { Button("Search Nearby", action: actions.searchNearby) }
            Divider()
            Button("Disconnect from \(page.macName)", action: actions.disconnect)
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.25)))
                    .overlay(Image(systemName: "desktopcomputer").font(.system(size: 16)))
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.macName).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 5) {
                        Circle().fill(page.locked == nil ? Color(red: 0.3, green: 0.85, blue: 0.39) : Color(red: 1, green: 0.62, blue: 0.2)).frame(width: 6, height: 6)
                        Text(page.status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Glass(cornerRadius: 11, fill: 0.14, stroke: 0.2))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .help("Connect to another Mac, add one, or disconnect")
        .accessibilityLabel("\(page.macName), \(page.status). Other Macs")
    }

    private func paneRow(_ p: Pane, _ title: String, _ symbol: String) -> some View {
        Button { pane = p } label: {
            sidebarLabel(title, symbol, selected: pane == p)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(pane == p ? .isSelected : [])
    }

    private func desktopRow(_ d: LauncherModel.Desktop) -> some View {
        Button { actions.open(.desktop(d.source)) } label: {
            sidebarLabel(d.name, "display", selected: false, open: d.isOpen)
        }
        .buttonStyle(.plain)
        .help(["Desktop", d.name == "Desktop" ? nil : d.name, d.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityLabel(["Desktop", d.name == "Desktop" ? nil : d.name, d.detail, d.isOpen ? "open" : nil]
            .compactMap { $0 }.joined(separator: ", "))
    }

    private func sidebarLabel(_ title: String, _ symbol: String, selected: Bool, open: Bool = false) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 16)
            Text(title).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
            if open { Circle().fill(.white.opacity(0.85)).frame(width: 5, height: 5) }
        }
        .foregroundStyle(.white.opacity(selected ? 1 : 0.88))
        .padding(.horizontal, 9).frame(height: 30)
        .background(SidebarHighlight(selected: selected))
        .contentShape(Rectangle())
    }

    private var sidebarSettings: some View {
        let s = page.settings
        return VStack(spacing: 0) {
            if let bitrate = s.bitrate {
                Menu { qualityItems(bitrate) } label: {
                    settingRow("Quality") {
                        Text(qualityName(bitrate) + (s.maxFPS.map { " · \($0)" } ?? "")).fontWeight(.semibold)
                    }
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .help("Quality and frame rate")
            }
            settingRow("Sound") { Toggle("", isOn: Binding(get: { s.soundOn }, set: { _ in actions.toggleSound() })) }
                .disabled(!s.soundAvailable)
                .help(s.soundAvailable ? "Play the other Mac’s sound here" : "\(page.macName)’s Sill does not send sound yet")
            settingRow("Capture shortcuts") { Toggle("", isOn: Binding(get: { s.captureOn }, set: { _ in actions.toggleCapture() })) }
                .help("⌘Tab, ⌘Space and the other shortcuts go to the other Mac while its window has the keyboard")
        }
        .toggleStyle(.switch).controlSize(.mini)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.18)))
    }

    private func settingRow<V: View>(_ label: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.75))
            Spacer(minLength: 4)
            value().labelsHidden()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 6).frame(height: 26)
        .contentShape(Rectangle())
    }

    /// Quality, then the frame rate, as one menu: the sidebar's row and the hidden sidebar's capsule.
    @ViewBuilder private func qualityItems(_ bitrate: Int) -> some View {
        let s = page.settings
        Section("Quality") {
            ForEach(s.qualities, id: \.bitrate) { q in
                Button { actions.setQuality(q.bitrate) } label: { checked(q.bitrate == bitrate, "\(q.name) — \(q.bitrate / 1_000_000) Mbps") }
            }
        }
        if let fps = s.maxFPS {
            Section("Frame rate") {
                ForEach(s.fpsChoices, id: \.self) { f in
                    Button { actions.setMaxFPS(f) } label: { checked(f == fps, "Up to \(f) fps") }
                }
            }
        }
    }

    private func qualityName(_ bitrate: Int) -> String {
        page.settings.qualities.first(where: { $0.bitrate == bitrate })?.name ?? "Custom"
    }

    @ViewBuilder private func checked(_ on: Bool, _ title: String) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    // MARK: Content

    private func content(_ model: LauncherModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            topBar
            if let why = page.locked {
                if why == .screenLocked, let desktop = model.desktops.first {
                    unlockTile(desktop)
                } else {
                    lockedCard(why)
                }
                Spacer(minLength: 0)
            } else if model.isEmpty && (pane != .favourites || !query.isEmpty) {
                emptyState
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 22) {
                        switch pane {
                        case .home:
                            if !model.windows.isEmpty || (sidebarHidden && !model.desktops.isEmpty) { openRow(model) }
                            if !model.favourites.isEmpty { favouritesShelf(model) } else if query.isEmpty { favouritesHint }
                            if !model.apps.isEmpty || !model.recent.isEmpty || query.isEmpty { allApps(model) }
                        case .favourites:
                            if model.favourites.isEmpty { favouritesHint } else { appGrid("Favourites", model.favourites, sortable: false) }
                        case .apps:
                            allApps(model)
                        }
                    }
                    .padding(.bottom, 14)
                }
                .scrollIndicators(.automatic)
            }
        }
        .padding(.leading, sidebarHidden ? 4 : 2).padding(.trailing, 14).padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            if sidebarHidden { Color.clear.frame(width: 70, height: 1) }   // the window's buttons
            else { sidebarButton }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 22, weight: .bold)).lineLimit(1)
                if sidebarHidden {
                    Text(page.status).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if sidebarHidden { sidebarButton }
            search
            if sidebarHidden { settingsCapsule }
        }
        .frame(height: 40)
    }

    /// Hides the sidebar from beside the title; while it is hidden, shows it from beside the search.
    private var sidebarButton: some View {
        Button(action: toggleSidebar) {
            Image(systemName: "sidebar.left").font(.system(size: 14))
                .frame(width: 32, height: 32)
                .background(Circle().fill(.white.opacity(sidebarHidden ? 0.14 : 0))
                    .overlay(Circle().strokeBorder(.white.opacity(sidebarHidden ? 0.2 : 0))))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("s", modifiers: [.control, .command])
        .help(sidebarHidden ? "Show Sidebar (⌃⌘S)" : "Hide Sidebar (⌃⌘S)")
        .accessibilityLabel(sidebarHidden ? "Show Sidebar" : "Hide Sidebar")
    }

    private var title: String {
        switch pane {
        case .home: sidebarHidden ? page.macName : "Home"
        case .favourites: "Favourites"
        case .apps: "All Apps"
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
            TextField("Search \(page.macName)", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit { if let first = model.firstChoice { actions.open(first) } }
                .accessibilityLabel("Search \(page.macName)")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 13)
        .frame(minWidth: 140, idealWidth: 260, maxWidth: 260)
        .frame(height: 32)
        .background(Glass(cornerRadius: 16, fill: 0.14, stroke: 0.2))
    }

    /// The settings while the sidebar is hidden: quality, sound, shortcuts and Disconnect as icons.
    private var settingsCapsule: some View {
        let s = page.settings
        return HStack(spacing: 2) {
            if let bitrate = s.bitrate {
                Menu { qualityItems(bitrate) } label: { capsuleIcon("chart.bar", on: false) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .help("Quality: \(qualityName(bitrate))" + (s.maxFPS.map { ", up to \($0) fps" } ?? ""))
            }
            Button(action: actions.toggleSound) { capsuleIcon(s.soundOn ? "speaker.wave.2" : "speaker.slash", on: s.soundOn) }
                .buttonStyle(.plain).disabled(!s.soundAvailable)
                .help(s.soundAvailable ? (s.soundOn ? "Sound on" : "Sound off") : "\(page.macName)’s Sill does not send sound yet")
            Button(action: actions.toggleCapture) { capsuleIcon("command", on: s.captureOn) }
                .buttonStyle(.plain)
                .help(s.captureOn ? "Shortcuts go to the other Mac" : "Shortcuts stay on this Mac")
            Button(action: actions.disconnect) {
                capsuleIcon("power", on: false, tint: Color(red: 1, green: 0.71, blue: 0.67))
            }
            .buttonStyle(.plain).help("Disconnect from \(page.macName)")
        }
        .padding(.horizontal, 3).frame(height: 32)
        .background(Glass(cornerRadius: 16, fill: 0.14, stroke: 0.2))
    }

    private func capsuleIcon(_ symbol: String, on: Bool, tint: Color = .white) -> some View {
        Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(tint)
            .frame(width: 30, height: 26)
            .background(Capsule().fill(.white.opacity(on ? 0.22 : 0)))
            .contentShape(Capsule())
    }

    /// A locked Mac, in place of every section: that its apps and windows come back with the unlock, or,
    /// for another user on it, what the iPhone's drawer says (LockedMac.line).
    private func lockedCard(_ why: LockedMac.Why) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: why == .otherUser ? "person.2.fill" : "lock.fill")
                .font(.system(size: 22)).frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(why == .otherUser ? "Another user is on \(page.macName)" : "\(page.macName) is locked")
                    .font(.system(size: 15, weight: .semibold))
                Text(why == .otherUser ? LockedMac.line(mac: page.macName, why: why)
                                       : "Unlock it to see its apps and windows here.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(Glass(cornerRadius: 16, fill: 0.12, stroke: 0.18))
        .accessibilityElement(children: .combine)
    }

    /// A locked Mac (design C, David's choice): its lock screen as a picture, what to do, and Unlock
    /// Desktop. The whole tile is one button that opens the Desktop window, which a locked Mac still streams
    /// (its lock screen, LockPolicy.lockScreenStreams), where a paired Mac types the password. The
    /// picture's clock is this Mac's time, kept current; the unlock badge sits in its corner, clear of it.
    private func unlockTile(_ desktop: LauncherModel.Desktop) -> some View {
        Button { actions.open(.desktop(desktop.source)) } label: {
            HStack(spacing: 24) {
                LockScreenPicture()
                VStack(alignment: .leading, spacing: 8) {
                    Label("\(page.macName) is locked", systemImage: "lock.fill")
                        .font(.system(size: 17, weight: .bold))
                    Text("Open its Desktop and type your password on the lock screen. Its apps and windows show here once it’s unlocked.")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.75))
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 7) {
                        Image(systemName: "lock.open.fill").font(.system(size: 13))
                        Text("Unlock Desktop").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Color(red: 0.09, green: 0.13, blue: 0.23))
                    .padding(.horizontal, 16).frame(height: 32)
                    .background(Capsule().fill(.white))
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(UnlockTileStyle())
        .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        .help("Open \(page.macName)’s Desktop to unlock it")
        .accessibilityLabel("\(page.macName) is locked. Unlock Desktop")
        .accessibilityHint("Opens its Desktop, where you type your password on the lock screen.")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(query.isEmpty ? "Still listing \(page.macName)’s apps…" : "Nothing on \(page.macName) matches “\(query)”")
                .font(.system(size: 15, weight: .medium))
            if !query.isEmpty {
                Text("Apps, window titles and display names are searched.")
                    .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Windows and Desktops

    private func openRow(_ model: LauncherModel) -> some View {
        section(model.windows.isEmpty ? "Desktops" : "Open windows") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    if sidebarHidden { ForEach(model.desktops, id: \.name) { d in desktopTile(d) } }
                    ForEach(model.windows, id: \.id) { w in windowTile(w) }
                }
                .padding(.vertical, 6).padding(.horizontal, 2)
            }
        }
    }

    private func card<Inside: View>(open: Bool, @ViewBuilder _ inside: () -> Inside) -> some View {
        ZStack { RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.92)); inside() }
            .frame(width: 206, height: 124)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(red: 0.5, green: 0.69, blue: 1), lineWidth: open ? 3 : 0))
            .shadow(color: .black.opacity(0.3), radius: 15, y: 10)
    }

    private func desktopTile(_ d: LauncherModel.Desktop) -> some View {
        Button { actions.open(.desktop(d.source)) } label: {
            VStack(spacing: 7) {
                card(open: d.isOpen) {
                    Image(systemName: "menubar.dock.rectangle").font(.system(size: 30, weight: .light)).foregroundStyle(.black.opacity(0.45))
                }
                caption(d.name, d.detail)
            }
        }
        .buttonStyle(LauncherTileStyle())
        .accessibilityLabel(["Desktop", d.name == "Desktop" ? nil : d.name, d.detail].compactMap { $0 }.joined(separator: ", "))
    }

    private func windowTile(_ w: LauncherModel.Window) -> some View {
        Button { actions.open(.window(w.id)) } label: {
            VStack(spacing: 7) {
                card(open: w.isOpen) {
                    if let picture = page.thumbnails[w.id] {
                        Image(nsImage: picture).resizable().scaledToFill()
                    } else {
                        appIcon(w.bundleID, name: w.appName, size: 48)
                    }
                }
                HStack(spacing: 7) {
                    appIcon(w.bundleID, name: w.appName, size: 16)
                    Text(w.title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: 206)
            }
        }
        .buttonStyle(LauncherTileStyle())
        .help(w.appName == w.title ? w.title : "\(w.title) — \(w.appName)")
        .accessibilityLabel("\(w.title), \(w.appName) window")
    }

    // MARK: Apps

    /// The favourites on Home: a Dock-like shelf, in the order added, a dot under the running ones.
    private func favouritesShelf(_ model: LauncherModel) -> some View {
        section("Favourites") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.favourites, id: \.bundleID) { a in
                        Button { actions.open(.app(a.bundleID)) } label: {
                            VStack(spacing: 5) {
                                appIcon(a.bundleID, name: a.name, size: 52)
                                Text(a.name).font(.system(size: 11)).foregroundStyle(.white.opacity(0.92))
                                    .lineLimit(1).truncationMode(.tail).frame(width: 72)
                                Circle().fill(.white.opacity(a.running ? 1 : 0)).frame(width: 4, height: 4)
                            }
                        }
                        .buttonStyle(LauncherTileStyle(padding: 2))
                        .modifier(AppMenu(app: a, actions: actions))
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)
                .background(Glass(cornerRadius: 22, fill: 0.12, stroke: 0.18))
                .padding(1)
            }
        }
    }

    private var favouritesHint: some View {
        section("Favourites") {
            HStack(spacing: 8) {
                Image(systemName: "star")
                Text("Right-click an app to add it to Favourites.")
            }
            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 16).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
    }

    /// All Apps: A to Z, or Recent, which holds only what was opened from here (apps and Desktops),
    /// latest first, and says so while it is empty.
    @ViewBuilder private func allApps(_ model: LauncherModel) -> some View {
        if page.input.appOrder == .recent && query.isEmpty {
            section("All Apps", trailing: { sortControl }) {
                if model.recent.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                        Text("Apps and Desktops you open from here show up here, the latest first.")
                    }
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 16).frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 110), spacing: 4)], spacing: 10) {
                        ForEach(Array(model.recent.enumerated()), id: \.offset) { _, item in
                            switch item {
                            case .app(let a): appTile(a)
                            case .desktop(let d): recentDesktopTile(d)
                            }
                        }
                    }
                }
            }
        } else {
            appGrid("All Apps", model.apps, sortable: true)
        }
    }

    /// A Desktop in Recent: a display's picture where an app's icon would be.
    private func recentDesktopTile(_ d: LauncherModel.Desktop) -> some View {
        Button { actions.open(.desktop(d.source)) } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.43, blue: 0.69), Color(red: 0.42, green: 0.29, blue: 0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Image(systemName: "menubar.dock.rectangle").font(.system(size: 22, weight: .light)))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
                    .frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
                Text(d.name).font(.system(size: 11)).foregroundStyle(.white.opacity(0.92)).lineLimit(1).truncationMode(.tail)
                Circle().fill(.white.opacity(d.isOpen ? 0.85 : 0)).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(LauncherTileStyle())
        .accessibilityLabel("\(d.name), Desktop" + (d.isOpen ? ", open" : ""))
    }

    private func appGrid(_ title: String, _ apps: [LauncherModel.App], sortable: Bool) -> some View {
        section(title, trailing: { if sortable { sortControl } }) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84, maximum: 110), spacing: 4)], spacing: 10) {
                ForEach(apps, id: \.bundleID) { a in appTile(a) }
            }
        }
    }

    private var sortControl: some View {
        HStack(spacing: 0) {
            sortButton("A–Z", .name)
            sortButton("Recent", .recent)
        }
        .padding(2)
        .background(Glass(cornerRadius: 14, fill: 0.12, stroke: 0.16))
        .help("Sort All Apps by name, or with the apps you used most recently from this Mac first")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sort")
    }

    private func sortButton(_ title: String, _ order: LauncherModel.AppOrder) -> some View {
        let on = page.input.appOrder == order
        return Button { actions.setAppOrder(order) } label: {
            Text(title).font(.system(size: 11, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Color(red: 0.09, green: 0.13, blue: 0.23) : .white.opacity(0.85))
                .padding(.horizontal, 12).frame(height: 20)
                .background(Capsule().fill(.white.opacity(on ? 0.9 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// An app: opens on a click; a right-click adds it to the favourites or takes it out.
    private func appTile(_ a: LauncherModel.App) -> some View {
        Button { actions.open(.app(a.bundleID)) } label: {
            VStack(spacing: 6) {
                appIcon(a.bundleID, name: a.name, size: 52)
                Text(a.name).font(.system(size: 11)).foregroundStyle(.white.opacity(0.92)).lineLimit(1).truncationMode(.tail)
                Circle().fill(.white.opacity(a.running ? 0.85 : 0)).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(LauncherTileStyle())
        .modifier(AppMenu(app: a, actions: actions))
    }

    @ViewBuilder private func appIcon(_ bundleID: String, name: String, size: CGFloat) -> some View {
        if let icon = page.icons[bundleID] {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
                .shadow(color: .black.opacity(size > 30 ? 0.25 : 0), radius: 5, y: 3)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Color(white: 0.45))
                .overlay(Text(String(name.prefix(1))).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white))
                .frame(width: size * 0.82, height: size * 0.82)
                .frame(width: size, height: size)
        }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        section(title, trailing: { EmptyView() }, content)
    }

    private func section<Trailing: View, Content: View>(_ title: String, @ViewBuilder trailing: () -> Trailing,
                                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                Spacer(minLength: 0)
                trailing()
            }
            content()
        }
    }

    private func caption(_ title: String, _ detail: String?) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).lineLimit(1).truncationMode(.tail)
            }
        }
        .frame(maxWidth: 206)
    }
}

/// An app's right-click menu and its accessibility, the same in the grid and on the shelf.
private struct AppMenu: ViewModifier {
    let app: LauncherModel.App
    let actions: LauncherActions

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button { actions.open(.app(app.bundleID)) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                Divider()
                Button { actions.toggleFavourite(app.bundleID) } label: {
                    app.isFavourite ? Label("Remove from Favourites", systemImage: "star.slash") : Label("Add to Favourites", systemImage: "star")
                }
            }
            .accessibilityLabel([app.name, app.running ? "running" : nil, app.isFavourite ? "favourite" : nil].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAction(named: app.isFavourite ? "Remove from Favourites" : "Add to Favourites") { actions.toggleFavourite(app.bundleID) }
    }
}

/// The launcher's backdrop: two big soft glows on deep blue, a wallpaper seen through frosted glass.
struct Backdrop: View {
    var body: some View {
        GeometryReader { g in
            ZStack {
                Color(red: 0.09, green: 0.13, blue: 0.23)
                glow(Color(red: 0.18, green: 0.36, blue: 0.56), radius: 420).position(x: 180, y: 100)
                glow(Color(red: 0.36, green: 0.25, blue: 0.48), radius: 460)
                    .position(x: g.size.width - 150, y: g.size.height - 110)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, radius: CGFloat) -> some View {
        RadialGradient(colors: [color.opacity(0.85), color.opacity(0.4), color.opacity(0)], center: .center,
                       startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
    }
}

/// The unlock tile: frosted, brighter under the pointer, dimmed while pressed.
private struct UnlockTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Tile(configuration: configuration) }

    private struct Tile: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(Glass(cornerRadius: 20, fill: hovering ? 0.16 : 0.10, stroke: hovering ? 0.28 : 0.18)
                    .shadow(color: .black.opacity(hovering ? 0.25 : 0), radius: 15, y: 10))
                .opacity(configuration.isPressed ? 0.75 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}

/// A Mac's lock screen in miniature: this Mac's time (as its menu bar writes it, 12- or 24-hour), kept
/// current each minute, the account's circle and the password field, and an unlock badge in the corner.
private struct LockScreenPicture: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.31, blue: 0.53), Color(red: 0.24, green: 0.18, blue: 0.39)],
                                     startPoint: .top, endPoint: .bottom))
            VStack(spacing: 7) {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 30, weight: .light)).monospacedDigit()
                }
                Spacer(minLength: 0)
                Circle().fill(.white.opacity(0.3)).frame(width: 28, height: 28)
                Capsule().fill(.white.opacity(0.22)).frame(width: 104, height: 16)
            }
            .padding(.top, 14).padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Image(systemName: "lock.open.fill").font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(.black.opacity(0.45)))
                .overlay(Circle().strokeBorder(.white.opacity(0.25)))
                .padding(10)
        }
        .frame(width: 250, height: 156)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.85), lineWidth: 3))
        .shadow(color: .black.opacity(0.35), radius: 17, y: 14)
        .accessibilityHidden(true)
    }
}

/// A frosted panel: a faint white fill with a hairline edge.
struct Glass: View {
    var cornerRadius: CGFloat
    var fill: Double
    var stroke: Double
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius).fill(.white.opacity(fill))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(stroke)))
    }
}

/// A sidebar row's background: lit when selected, faint under the pointer.
private struct SidebarHighlight: View {
    let selected: Bool
    @State private var hovering = false
    var body: some View {
        RoundedRectangle(cornerRadius: 9).fill(.white.opacity(selected ? 0.18 : hovering ? 0.08 : 0))
            .onHover { hovering = $0 }
    }
}

/// A tile that brightens under the pointer and dims while pressed.
struct LauncherTileStyle: ButtonStyle {
    var padding: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        LauncherTile(configuration: configuration, padding: padding)
    }

    private struct LauncherTile: View {
        let configuration: ButtonStyleConfiguration
        let padding: CGFloat
        @State private var hovering = false
        var body: some View {
            configuration.label
                .padding(padding)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(hovering ? 0.1 : 0)))
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onHover { hovering = $0 }
        }
    }
}
