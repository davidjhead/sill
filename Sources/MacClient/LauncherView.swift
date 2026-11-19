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
}

/// What the launcher's buttons do. Each opening one closes the launcher first (Launcher).
struct LauncherActions {
    var open: (LauncherModel.Choice) -> Void = { _ in }
    var close: () -> Void = {}
    var setQuality: (Int) -> Void = { _ in }
    var setMaxFPS: (Int) -> Void = { _ in }
    var toggleSound: () -> Void = {}
    var toggleCapture: () -> Void = {}
    var disconnect: () -> Void = {}
}

/// The launcher's overlay, as the "Launchpad overlay" design has it: the other Mac and a search at the
/// top, its Desktops and open windows in a row, every app in a grid (a dot under the running ones), and
/// its settings as chips at the bottom. Drawn over Launcher's blurred, dimmed backdrop.
struct LauncherView: View {
    let page: LauncherPage
    let actions: LauncherActions
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var model: LauncherModel { LauncherModel.make(page.input, query: query) }

    var body: some View {
        let model = self.model
        ZStack {
            // A click on the backdrop, outside every tile, closes it, as Launchpad's does.
            Color.black.opacity(0.001).onTapGesture { actions.close() }
            VStack(alignment: .leading, spacing: 24) {
                header
                if model.isEmpty {
                    emptyState
                } else {
                    if !model.desktops.isEmpty || !model.windows.isEmpty { openRow(model) }
                    if !model.apps.isEmpty { appGrid(model) }
                    Spacer(minLength: 0)
                }
                settingsChips
            }
            .frame(maxWidth: 1120)
            .padding(.horizontal, 48)
            .padding(.top, 40)
            .padding(.bottom, 32)
        }
        .foregroundStyle(.white)
        .onAppear { searchFocused = true }
        .onExitCommand { actions.close() }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text(page.macName).fontWeight(.semibold)
                Text(page.status).foregroundStyle(.white.opacity(0.7))
            }
            .font(.system(size: 13))
            .frame(width: 280, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.7))
                TextField("Search apps, windows and displays", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { if let first = model.firstChoice { actions.open(first) } }
                    .accessibilityLabel("Search \(page.macName)")
            }
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .frame(width: 380, height: 36)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.2)))
            Spacer(minLength: 0)
            Text("esc to close")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 280, alignment: .trailing)
        }
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

    // MARK: Desktops and windows

    private func openRow(_ model: LauncherModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 40) {
                if !model.desktops.isEmpty {
                    section("Desktops") {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(model.desktops, id: \.name) { d in desktopTile(d) }
                        }
                    }
                }
                if !model.windows.isEmpty {
                    section("Open windows") {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(model.windows, id: \.id) { w in windowTile(w) }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func desktopTile(_ d: LauncherModel.Desktop) -> some View {
        Button { actions.open(.desktop(d.source)) } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.18, green: 0.2, blue: 0.25))
                    .overlay(Image(systemName: "menubar.dock.rectangle").font(.system(size: 26, weight: .light))
                        .foregroundStyle(.white.opacity(0.75)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(d.isOpen ? Color.accentColor : .white.opacity(0.2),
                                                                             lineWidth: d.isOpen ? 2 : 1))
                    .frame(width: 150, height: 92)
                caption(d.name, d.detail, width: 150)
            }
        }
        .buttonStyle(LauncherTileStyle())
        .accessibilityLabel(["Desktop", d.name == "Desktop" ? nil : d.name, d.detail].compactMap { $0 }.joined(separator: ", "))
    }

    private func windowTile(_ w: LauncherModel.Window) -> some View {
        Button { actions.open(.window(w.id)) } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.92))
                    if let picture = page.thumbnails[w.id] {
                        Image(nsImage: picture).resizable().scaledToFill()
                    } else {
                        appIcon(w.bundleID, name: w.appName, size: 44)
                    }
                }
                .frame(width: 164, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(w.isOpen ? Color.accentColor : .clear, lineWidth: 2))
                caption(w.title, w.appName == w.title ? nil : w.appName, width: 164)
            }
        }
        .buttonStyle(LauncherTileStyle())
        .accessibilityLabel("\(w.title), \(w.appName) window")
    }

    // MARK: Apps

    private func appGrid(_ model: LauncherModel) -> some View {
        section("Apps") {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 132), spacing: 8)], spacing: 18) {
                    ForEach(model.apps, id: \.bundleID) { a in
                        Button { actions.open(.app(a.bundleID)) } label: {
                            VStack(spacing: 7) {
                                appIcon(a.bundleID, name: a.name, size: 64)
                                Text(a.name).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                                Circle().fill(.white.opacity(a.running ? 0.85 : 0)).frame(width: 4, height: 4)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LauncherTileStyle())
                        .accessibilityLabel(a.running ? "\(a.name), running" : a.name)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder private func appIcon(_ bundleID: String, name: String, size: CGFloat) -> some View {
        if let icon = page.icons[bundleID] {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(Color(white: 0.45))
                .overlay(Text(String(name.prefix(1))).font(.system(size: size * 0.42, weight: .semibold)))
                .frame(width: size * 0.82, height: size * 0.82)
                .frame(width: size, height: size)
        }
    }

    // MARK: Settings

    private var settingsChips: some View {
        let s = page.settings
        return HStack(spacing: 10) {
            Spacer(minLength: 0)
            if let bitrate = s.bitrate {
                Menu {
                    ForEach(s.qualities, id: \.bitrate) { q in
                        Button { actions.setQuality(q.bitrate) } label: {
                            checked(q.bitrate == bitrate, "\(q.name) — \(q.bitrate / 1_000_000) Mbps")
                        }
                    }
                } label: { chip("Quality", s.qualities.first(where: { $0.bitrate == bitrate })?.name ?? "Custom") }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                if let fps = s.maxFPS {
                    Menu {
                        ForEach(s.fpsChoices, id: \.self) { f in
                            Button { actions.setMaxFPS(f) } label: { checked(f == fps, "Up to \(f) fps") }
                        }
                    } label: { chip("Frame rate", "\(fps) fps") }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
            }
            Button(action: actions.toggleSound) { chip("Sound", s.soundOn ? "On" : "Off") }
                .buttonStyle(.plain).disabled(!s.soundAvailable)
                .help(s.soundAvailable ? "Play the other Mac’s sound here" : "\(page.macName)’s Sill does not send sound yet")
            Button(action: actions.toggleCapture) { chip("Shortcuts", s.captureOn ? "Captured" : "This Mac") }
                .buttonStyle(.plain)
                .help("⌘Tab, ⌘Space and the other shortcuts go to the other Mac while its window has the keyboard")
            Button(action: actions.disconnect) { chip("Session", "Disconnect") }.buttonStyle(.plain)
            Spacer(minLength: 0)
        }
    }

    private func chip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.white.opacity(0.65))
            Text(value).fontWeight(.medium)
        }
        .font(.system(size: 12))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(.white.opacity(0.1)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
        .contentShape(Capsule())
    }

    @ViewBuilder private func checked(_ on: Bool, _ title: String) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.65))
            content()
        }
    }

    private func caption(_ title: String, _ detail: String?, width: CGFloat) -> some View {
        VStack(spacing: 1) {
            Text(title).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
            if let detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).lineLimit(1).truncationMode(.tail)
            }
        }
        .frame(width: width)
    }
}

/// A tile that brightens under the pointer and dims while pressed.
private struct LauncherTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LauncherTile(configuration: configuration)
    }

    private struct LauncherTile: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(hovering ? 0.1 : 0)))
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onHover { hovering = $0 }
        }
    }
}
