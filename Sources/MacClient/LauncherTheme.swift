import SwiftUI

/// The launcher's look (LauncherView, WelcomeView, Add a Mac): its backdrop and glows, the colour of its
/// text and glass, and the few colours that mean something (connected, warning, Disconnect). Three, chosen
/// in the sidebar's settings and kept for every Mac (`launcher.theme`): Midnight (deep blue and purple,
/// the first), Graphite (neutral dark grey, no colour) and Daylight (light, frosted white, dark text).
/// The window's own appearance (menus, the title bar's buttons, switches) follows `scheme`.
struct LauncherTheme: Equatable, Identifiable {
    enum ID: String, CaseIterable { case midnight, graphite, daylight }

    let id: ID
    let name: String
    let scheme: ColorScheme
    /// The backdrop: a colour under two soft glows, top left and bottom right.
    let base: Color
    let glowA: Color
    let glowB: Color
    /// Text and symbols, and the faint fills and edges drawn from it (selection, hover, dashed hints).
    let ink: Color
    /// Glass panels (the sidebar, cards, the search): `glass` at a panel's fill times `glassBoost`, its
    /// edge `edge` at the panel's stroke times `edgeScale`.
    let glass: Color
    let glassBoost: Double
    let edge: Color
    let edgeScale: Double
    /// A recessed area inside glass (the sidebar's settings).
    let well: Color
    /// The main button (Unlock Desktop, Pair, the chosen sort) and the text on it.
    let pill: Color
    let onPill: Color
    /// An open window's ring, the connected and warning dots, and Disconnect.
    let ring: Color
    let ok: Color
    let warn: Color
    let danger: Color

    static let midnight = LauncherTheme(
        id: .midnight, name: "Midnight", scheme: .dark,
        base: Color(red: 0.09, green: 0.13, blue: 0.23),
        glowA: Color(red: 0.18, green: 0.36, blue: 0.56), glowB: Color(red: 0.36, green: 0.25, blue: 0.48),
        ink: .white, glass: .white, glassBoost: 1, edge: .white, edgeScale: 1, well: .black.opacity(0.18),
        pill: .white, onPill: Color(red: 0.09, green: 0.13, blue: 0.23),
        ring: Color(red: 0.5, green: 0.69, blue: 1), ok: Color(red: 0.3, green: 0.85, blue: 0.39),
        warn: Color(red: 1, green: 0.62, blue: 0.2), danger: Color(red: 1, green: 0.71, blue: 0.67))

    static let graphite = LauncherTheme(
        id: .graphite, name: "Graphite", scheme: .dark,
        base: Color(red: 0.105, green: 0.105, blue: 0.115),
        glowA: Color(red: 0.27, green: 0.27, blue: 0.29), glowB: Color(red: 0.22, green: 0.21, blue: 0.20),
        ink: .white, glass: .white, glassBoost: 0.8, edge: .white, edgeScale: 0.7, well: .black.opacity(0.22),
        pill: Color(white: 0.93), onPill: Color(white: 0.1),
        ring: Color(red: 1, green: 0.74, blue: 0.3), ok: Color(red: 0.3, green: 0.85, blue: 0.39),
        warn: Color(red: 1, green: 0.62, blue: 0.2), danger: Color(red: 1, green: 0.55, blue: 0.5))

    static let daylight = LauncherTheme(
        id: .daylight, name: "Daylight", scheme: .light,
        base: Color(red: 0.92, green: 0.93, blue: 0.96),
        glowA: Color(red: 0.62, green: 0.76, blue: 0.97), glowB: Color(red: 0.86, green: 0.74, blue: 0.94),
        ink: Color(red: 0.11, green: 0.12, blue: 0.15), glass: .white, glassBoost: 5, edge: .black, edgeScale: 0.45,
        well: .black.opacity(0.05),
        pill: Color(red: 0.11, green: 0.12, blue: 0.15), onPill: .white,
        ring: Color(red: 0.16, green: 0.45, blue: 0.95), ok: Color(red: 0.13, green: 0.6, blue: 0.25),
        warn: Color(red: 0.85, green: 0.45, blue: 0.05), danger: Color(red: 0.78, green: 0.18, blue: 0.13))

    static let all: [LauncherTheme] = [.midnight, .graphite, .daylight]

    static func named(_ raw: String?) -> LauncherTheme {
        all.first { $0.id.rawValue == raw } ?? .midnight
    }

    /// The user defaults key the theme is kept under, for every Mac.
    static let key = "launcher.theme"
}

private struct LauncherThemeKey: EnvironmentKey { static let defaultValue = LauncherTheme.midnight }

extension EnvironmentValues {
    var launcherTheme: LauncherTheme {
        get { self[LauncherThemeKey.self] }
        set { self[LauncherThemeKey.self] = newValue }
    }
}
