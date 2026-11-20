import AppKit
import SwiftUI
import StreamProtocol

/// The launcher's window before a session (option 3 of the connect designs, David's choice with the
/// switcher on the Mac's name once connected): "Choose a Mac", the Macs the network lists and the saved
/// ones away from home as cards, each saying how it is reached (Wired, Wi-Fi, Direct, Remote, Not paired,
/// Update Sill), an Add a Mac card, the status line, and Search Nearby with its hint. A right-click on a
/// card offers Connect Remotely and Forget. Add a Mac and a Mac's pairing code are a page of the same
/// window (AddMacView). All of it is the shared StreamClient's, as the Connect window's was (it is gone).
struct WelcomeView: View {
    @ObservedObject var client: StreamClient
    @ObservedObject var page: ConnectPage
    @Environment(\.launcherTheme) private var theme

    var body: some View {
        ZStack {
            if page.showsAddMac(client) {
                AddMacView(client: client, page: page)
            } else {
                chooser
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Backdrop())
        .foregroundStyle(theme.ink)
        .environment(\.colorScheme, theme.scheme)
    }

    private var chooser: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Choose a Mac").font(.system(size: 30, weight: .bold))
                HStack(spacing: 7) {
                    if client.macs.isEmpty || isWorking { ProgressView().controlSize(.small) }
                    Text(client.status).font(.system(size: 13)).foregroundStyle(theme.ink.opacity(0.75))
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                if let notice = client.notice, notice.storeLink, notice.text == client.status {
                    Text("Update Sill on this Mac to keep using that Mac.").font(.system(size: 12)).foregroundStyle(theme.ink.opacity(0.75))
                }
                PairingLine(pairing: client.pairing)
            }
            .padding(.top, 70)
            ScrollView(.vertical) {
                // As many columns as fit, at most the cards there are, so a few cards sit in the middle.
                let columns = Array(repeating: GridItem(.fixed(168), spacing: 18), count: max(1, min(client.macs.count + 1, 4)))
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(client.macs) { mac in macCard(mac) }
                    addCard
                }
                .padding(.horizontal, 40).padding(.vertical, 36)
            }
            if client.showsNearbyHint {
                VStack(spacing: 10) {
                    if client.searchingNearby {
                        Text("Also looking nearby").font(.system(size: 12)).foregroundStyle(theme.ink.opacity(0.7))
                    } else {
                        Button { client.searchNearby() } label: {
                            Text("Search Nearby").font(.system(size: 12)).padding(.horizontal, 16).frame(height: 28)
                                .background(Glass(cornerRadius: 14, fill: 0.12, stroke: 0.2)).contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Also looks for a Mac with Direct Wireless Connection turned on, without a Wi-Fi network.")
                    }
                    Text("The other Mac has to be on the same network as this one, or have Direct Wireless Connection turned on in Sill. Away from home, add it once with a code from that Mac.")
                        .font(.system(size: 11.5)).foregroundStyle(theme.ink.opacity(0.55))
                        .multilineTextAlignment(.center).frame(maxWidth: 520)
                }
                .padding(.bottom, 26)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var isWorking: Bool { if case .working = client.pairing { return true }; return false }

    private func macCard(_ mac: FoundMac) -> some View {
        let ready = mac.word != "Not paired" && mac.word != "Update Sill"
        return Button { client.connect(to: mac) } label: {
            VStack(spacing: 10) {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: Self.screen(mac.name), startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.85), lineWidth: 3))
                        .frame(width: 104, height: 70)
                    UnevenRoundedRectangle(bottomLeadingRadius: 4, bottomTrailingRadius: 4).fill(.white.opacity(0.6)).frame(width: 30, height: 6)
                }
                .opacity(ready ? 1 : 0.45)
                Text(mac.name).font(.system(size: 14, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                if let word = mac.word {
                    HStack(spacing: 5) {
                        Circle().fill(dot(mac)).frame(width: 6, height: 6)
                        Text(word).font(.system(size: 11.5)).foregroundStyle(theme.ink.opacity(0.7))
                    }
                }
            }
            .padding(.top, 18).padding(.bottom, 14).padding(.horizontal, 12)
            .frame(width: 168)
            .background(Glass(cornerRadius: 18, fill: ready ? 0.12 : 0.06, stroke: ready ? 0.2 : 0.1)
                .shadow(color: .black.opacity(0.2), radius: 15, y: 12))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(LauncherTileStyle(padding: 0))
        .contextMenu {
            if let id = mac.macID {
                if mac.route == .network { Button("Connect Remotely") { client.connectRemotely(id) } }
                let name = client.savedMac(id) != nil ? client.displayName(id) : mac.name
                Button("Forget \(name)", role: .destructive) { client.forget(id) }
            }
        }
        .accessibilityLabel(mac.route == .remote ? "\(mac.name), Remote" : mac.homeWord.label(name: mac.name))
    }

    private var addCard: some View {
        Button { page.startAdding(client) } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44).background(Circle().fill(theme.ink.opacity(0.12)))
                Text("Add a Mac").font(.system(size: 13, weight: .semibold))
                Text("With a code, at home or away").font(.system(size: 11)).foregroundStyle(theme.ink.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .frame(width: 168, height: 150)
            .background(RoundedRectangle(cornerRadius: 18).strokeBorder(theme.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(LauncherTileStyle(padding: 0))
    }

    /// A screen colour of each Mac's own, from its name, so the cards tell apart at a glance.
    static func screen(_ name: String) -> [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.24, green: 0.43, blue: 0.69), Color(red: 0.42, green: 0.29, blue: 0.55)],
            [Color(red: 0.18, green: 0.56, blue: 0.48), Color(red: 0.24, green: 0.43, blue: 0.69)],
            [Color(red: 0.69, green: 0.42, blue: 0.24), Color(red: 0.55, green: 0.29, blue: 0.42)],
            [Color(red: 0.36, green: 0.36, blue: 0.62), Color(red: 0.20, green: 0.55, blue: 0.70)],
        ]
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palettes[abs(sum) % palettes.count]
    }

    func dot(_ mac: FoundMac) -> Color {
        if mac.route == .remote { return theme.ring }
        switch mac.word {
        case "Not paired"?: return Color(white: 0.55)
        case "Update Sill"?: return theme.warn
        default: return theme.ok
        }
    }
}

/// Whether the window shows Add a Mac (from the Add a Mac card, or the switcher's item while connected),
/// kept by the launcher (Launcher) so it survives the session's start or end.
final class ConnectPage: ObservableObject {
    @Published var adding = false

    /// Add a Mac shows for a pairing link waiting for its yes, a Mac showing its code, or a choice of Add.
    func showsAddMac(_ client: StreamClient) -> Bool {
        adding || client.pendingLink != nil || client.homeAsk.map { $0.phase == .shown } == true
    }

    func startAdding(_ client: StreamClient) {
        client.cancelHomeAsk()
        client.pairing = .idle
        adding = true
    }

    func done(_ client: StreamClient) {
        if case .working = client.pairing { client.cancelPairing() }
        client.pairing = .idle
        client.cancelHomeAsk()
        adding = false
    }
}

/// Pairing's state in a line: working, paired or failed.
private struct PairingLine: View {
    let pairing: PairingPhase
    @Environment(\.launcherTheme) private var theme
    var body: some View {
        switch pairing {
        case .idle: EmptyView()
        case .working(let text): Label(text, systemImage: "hourglass").font(.system(size: 12)).foregroundStyle(theme.ink.opacity(0.75))
        case .paired(let name): Label("Paired with \(name).", systemImage: "checkmark.circle").font(.system(size: 12)).foregroundStyle(theme.ok)
        case .failed(let problem): Label(problem.text, systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(theme.warn)
        }
    }
}

/// Add a Mac, a page of the launcher's window: a Mac's 12-digit code when it shows one (a Not paired
/// card's click), or, from Add a Mac, the address and code away from home or a pairing link; a pasted or
/// opened link asks first.
struct AddMacView: View {
    enum Way: Hashable { case network, away, link }

    @ObservedObject var client: StreamClient
    @ObservedObject var page: ConnectPage
    @Environment(\.launcherTheme) private var theme
    @State private var way = Way.network
    @State private var homeCode = ""
    @State private var address = ""
    @State private var code = ""
    @State private var link = ""

    private var homeShown: HomeAsk? { client.homeAsk.flatMap { $0.phase == .shown ? $0 : nil } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { page.done(client) } label: {
                    Label("Back", systemImage: "chevron.left").font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 11).frame(height: 24)
                        .background(Glass(cornerRadius: 12, fill: 0.12, stroke: 0.2)).contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Back (Escape)")
                Spacer()
            }
            .padding(.leading, 76).padding(.top, 8)   // beside the window's buttons
            column
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .textFieldStyle(.plain)
        .onChange(of: client.connected) { _, connected in if connected { page.adding = false } }
    }

    private var column: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 26, weight: .bold))
            PairingLine(pairing: client.pairing)
            if let pending = client.pendingLink {
                confirm(pending)
            } else if let ask = homeShown {
                homeCard(ask)
            } else {
                picker
                switch way {
                case .network: networkCard
                case .away: awayCard
                case .link: linkCard
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 24)
        .frame(maxWidth: 680, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var title: String {
        if let ask = homeShown { return DiscoveryPolicy.HomeCopy.cardTitle(mac: ask.name) }
        return "Add a Mac"
    }

    private var picker: some View {
        HStack(spacing: 4) {
            tab("On this network", .network)
            tab("Away from home", .away)
            tab("Pairing link", .link)
        }
        .padding(3)
        .background(Glass(cornerRadius: 16, fill: 0.10, stroke: 0.16))
    }

    private func tab(_ title: String, _ w: Way) -> some View {
        Button { way = w } label: {
            Text(title).font(.system(size: 12, weight: way == w ? .semibold : .regular))
                .foregroundStyle(way == w ? theme.onPill : theme.ink.opacity(0.85))
                .padding(.horizontal, 14).frame(height: 26)
                .background(Capsule().fill(theme.pill.opacity(way == w ? 0.9 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(way == w ? .isSelected : [])
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) { content() }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Glass(cornerRadius: 18, fill: 0.10, stroke: 0.18))
    }

    private func field(_ title: String, _ text: Binding<String>, prompt: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.ink.opacity(0.6))
            TextField(title, text: text, prompt: Text(prompt).foregroundStyle(theme.ink.opacity(0.35)))
                .font(mono ? .system(size: 18, weight: .medium, design: .monospaced) : .system(size: 14))
                .padding(.horizontal, 12).frame(height: mono ? 42 : 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(theme.well.opacity(2)))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.ink.opacity(0.18)))
        }
    }

    private func primary(_ title: String, enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.onPill)
                .padding(.horizontal, 22).frame(height: 32)
                .background(Capsule().fill(theme.pill)).contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .disabled(!enabled).opacity(enabled ? 1 : 0.5)
    }

    private func digits(_ s: String) -> Int { s.filter(\.isNumber).count }

    private var networkCard: some View {
        card {
            Label("Choose the Mac on the welcome page", systemImage: "desktopcomputer").font(.system(size: 15, weight: .semibold))
            Text("A Mac on this network that is not paired yet says “Not paired”. Click it, and it shows a 12-digit code in Sill’s window to type here. Not near it? Use “Away from home” with the address and code from its Sill window.")
                .font(.system(size: 12.5)).foregroundStyle(theme.ink.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func homeCard(_ ask: HomeAsk) -> some View {
        card {
            Text("Enter the 12-digit code \(ask.name) shows.").font(.system(size: 13)).foregroundStyle(theme.ink.opacity(0.8))
            field("Code", $homeCode, prompt: "0000 0000 0000", mono: true)
                .onSubmit { client.pairHome(code: homeCode) }
            HStack {
                Spacer()
                Button("Cancel") { client.cancelHomeAsk(); homeCode = "" }.buttonStyle(.plain).padding(.horizontal, 10)
                primary("Pair", enabled: digits(homeCode) >= 12) { client.pairHome(code: homeCode) }
            }
        }
        .onDisappear { homeCode = "" }
    }

    private var awayCard: some View {
        card {
            Text("The other Mac’s Sill shows its address and a code when you choose to pair a device away from home.")
                .font(.system(size: 12.5)).foregroundStyle(theme.ink.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            field("Address", $address, prompt: "name.tailnet.ts.net or 100.101.102.103")
            field("Code", $code, prompt: "12 digits", mono: true)
            HStack {
                Spacer()
                primary("Pair", enabled: !address.isEmpty && digits(code) >= 12) {
                    client.pairTyped(code: code, address: address, overlay: false)
                }
            }
        }
    }

    private var linkCard: some View {
        card {
            Text("A sill://pair link, copied from the other Mac’s pairing window or sent to you in Messages.")
                .font(.system(size: 12.5)).foregroundStyle(theme.ink.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            field("Link", $link, prompt: "sill://pair?…")
            HStack {
                Button("Paste") { link = NSPasteboard.general.string(forType: .string) ?? link }.buttonStyle(.plain)
                Spacer()
                primary("Pair with Link", enabled: !link.isEmpty) {
                    switch PairLink.parse(link.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    case .success(let parsed): client.scanned(parsed, tapped: true, overlay: false)
                    case .failure: client.pairing = .failed(.notALink)
                    }
                }
            }
        }
    }

    private func confirm(_ pending: PairLink) -> some View {
        card {
            Text("Pair this Mac with \(pending.name)?").font(.system(size: 15, weight: .semibold))
            HStack {
                Spacer()
                Button("Cancel") { client.cancelPendingLink() }.buttonStyle(.plain).padding(.horizontal, 10)
                primary("Pair", enabled: true) { page.adding = true; client.confirmPendingLink() }
            }
        }
    }
}
