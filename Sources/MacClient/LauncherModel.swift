import Foundation
import StreamProtocol

/// The launcher (Launcher.swift, LauncherView.swift): what the other Mac offers to open, in the
/// sections the launcher shows, and what a search keeps of them.
///
/// - Desktops: one per display of a host that lists its `displays` (#66's, each a Desktop window of its
///   own); else the one Desktop, named after the display it shows when the host says (#91's stops).
/// - Windows: the host's windows in the bar's order, each by its title (its app's name when untitled).
/// - Favourites: the apps added to them here (a right-click on an app), in the order added; one the
///   other Mac no longer lists is left out, and comes back if it does again.
/// - Apps: every installed app, with any app that has a window but is not installed in a listed folder
///   added; `running` when it has a window. A to Z; or Recent: only the apps used from this Mac (opened
///   from the launcher, or one of their windows taking the keyboard), latest first, none before any is.
/// - Recent: Recent's whole list, the apps used and the Desktops opened from this Mac together, latest
///   first (a tie A to Z); empty in the A to Z order.
///
/// A search (case and accents ignored) keeps what matches: a name or a word in it starting with the
/// query first, then names containing it, each in its section's order (a search looks through every
/// app in either order, and through Recent's list too). Return opens `firstChoice`:
/// the first app, else the first window, else the first Desktop.
///
/// Pure: Foundation and StreamProtocol only, checked with swiftc (Tests/checks/launcher).
struct LauncherModel: Equatable {
    struct Desktop: Equatable {
        var source: StreamSource
        var name: String
        var detail: String?
        var isOpen: Bool
    }

    struct Window: Equatable {
        var id: UInt32
        var title: String
        var appName: String
        var bundleID: String
        var isOpen: Bool
    }

    struct App: Equatable {
        var bundleID: String
        var name: String
        var running: Bool
        var isFavourite = false
    }

    /// How All Apps is sorted.
    enum AppOrder: String, Equatable, CaseIterable {
        case name      // A to Z
        case recent    // most recently used first
    }

    /// One of Recent's tiles: an app used, or a Desktop opened, from this Mac.
    enum RecentItem: Equatable {
        case app(App)
        case desktop(Desktop)

        var name: String {
            switch self {
            case .app(let a): a.name
            case .desktop(let d): d.name == "Desktop" ? "Desktop" : d.name
            }
        }
    }

    enum Choice: Equatable {
        case desktop(StreamSource)
        case window(UInt32)
        case app(String)
    }

    /// What the client knows of the other Mac, as the launcher reads it.
    struct Input: Equatable {
        var windows: [WindowInfo] = []          // in the bar's order (StreamClient.orderedWindows)
        var apps: [AppInfo] = []
        var hostDisplays: [DisplayInfo] = []    // #66's host: each display a Desktop window
        var desktopNames: [String]? = nil       // #91's stops, main's host
        var desktopCurrent: Int? = nil          // counting from 1
        var open: Set<StreamSource> = []        // sources with a window open here
        var favourites: [String] = []           // bundle IDs, in the order added
        var recents: [String: Double] = [:]     // bundle ID, or a Desktop's `recentKey` → when last used from this Mac (seconds)
        var appOrder: AppOrder = .name
    }

    var desktops: [Desktop]
    var windows: [Window]
    var favourites: [App] = []
    var apps: [App]
    var recent: [RecentItem] = []

    var isEmpty: Bool { desktops.isEmpty && windows.isEmpty && favourites.isEmpty && apps.isEmpty && recent.isEmpty }

    /// The key a Desktop's use is kept under in `Input.recents`, beside the apps' bundle IDs.
    static func recentKey(_ source: StreamSource) -> String {
        switch source {
        case .window(let id): return "desktop:\(id)"
        default: return "desktop"
        }
    }

    var firstChoice: Choice? {
        if let a = apps.first { return .app(a.bundleID) }
        if let w = windows.first { return .window(w.id) }
        if let d = desktops.first { return .desktop(d.source) }
        return nil
    }

    static func make(_ input: Input, query: String = "") -> LauncherModel {
        let apps = apps(input)
        // The favourites from every app the other Mac lists, whatever All Apps' order: Recent's list holds
        // only the apps used, and a favourite never opened from here is a favourite still.
        let every = input.appOrder == .name ? apps : Self.apps(named(input))
        let byID = Dictionary(every.map { ($0.bundleID, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        let favourites = input.favourites.compactMap { id in seen.insert(id).inserted ? byID[id] : nil }
        let desktops = desktops(input)
        let all = LauncherModel(desktops: desktops, windows: windows(input), favourites: favourites, apps: apps,
                                recent: input.appOrder == .recent ? recent(apps, desktops, input.recents) : [])
        let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return all }
        return LauncherModel(desktops: ranked(all.desktops, q) { [$0.name, $0.detail ?? ""] },
                             windows: ranked(all.windows, q) { [$0.title, $0.appName] },
                             favourites: ranked(all.favourites, q) { [$0.name] },
                             apps: ranked(input.appOrder == .name ? all.apps : Self.apps(named(input)), q) { [$0.name] },   // every app, whatever the order
                             recent: ranked(all.recent, q) { [$0.name] })
    }

    private static func named(_ input: Input) -> Input { var i = input; i.appOrder = .name; return i }

    /// Recent's list: the used apps (already latest first) and the Desktops opened, merged by when.
    private static func recent(_ apps: [App], _ desktops: [Desktop], _ recents: [String: Double]) -> [RecentItem] {
        let items = apps.compactMap { a in recents[a.bundleID].map { (t: $0, item: RecentItem.app(a)) } }
            + desktops.compactMap { d in recents[recentKey(d.source)].map { (t: $0, item: RecentItem.desktop(d)) } }
        return items.sorted { a, b in
            if a.t != b.t { return a.t > b.t }
            return a.item.name.localizedStandardCompare(b.item.name) == .orderedAscending
        }.map(\.item)
    }

    /// An app's windows on the other Mac that opening it from here shows, front to back as listed: titled,
    /// and not one of its strips (a browser's full-screen bar, 115 points tall). An app with any is
    /// running there, and asking it to launch only brings it forward with no new window, so the other
    /// Mac's Sill (which streams a launched app's new window) streamed nothing: these open instead.
    static func openableWindows(of bundleID: String, in windows: [WindowInfo]) -> [WindowInfo] {
        windows.filter { $0.bundleID == bundleID && !$0.title.isEmpty && $0.width >= 80 && $0.height >= 150 }
    }

    /// The favourites after a right-click's Add or Remove: added at the end, removed wherever it is.
    static func toggled(_ favourites: [String], _ bundleID: String) -> [String] {
        favourites.contains(bundleID) ? favourites.filter { $0 != bundleID } : favourites + [bundleID]
    }

    // MARK: Sections

    private static func desktops(_ input: Input) -> [Desktop] {
        if !input.hostDisplays.isEmpty {
            let many = input.hostDisplays.count > 1
            return input.hostDisplays.map { d in
                let source = StreamSource.window(DesktopWindow.id(display: d.id))
                return Desktop(source: source, name: many ? d.name : "Desktop",
                               detail: many ? (d.main == true ? "Main display" : nil) : d.name,
                               isOpen: input.open.contains(source))
            }
        }
        var detail: String?
        if let names = input.desktopNames, names.count > 1, let n = input.desktopCurrent, (1...names.count).contains(n) {
            let name = names[n - 1].trimmingCharacters(in: .whitespacesAndNewlines)
            detail = (name.isEmpty ? "Display \(n)" : name) + " · \(n) of \(names.count)"
        }
        return [Desktop(source: .desktop, name: "Desktop", detail: detail, isOpen: input.open.contains(.desktop))]
    }

    private static func windows(_ input: Input) -> [Window] {
        input.windows.map { w in
            Window(id: w.id, title: w.title.isEmpty ? w.appName : w.title, appName: w.appName,
                   bundleID: w.bundleID, isOpen: input.open.contains(.window(w.id)))
        }
    }

    private static func apps(_ input: Input) -> [App] {
        let running = Set(input.windows.map(\.bundleID))
        let favourite = Set(input.favourites)
        var seen = Set<String>()
        var apps: [App] = []
        for a in input.apps where seen.insert(a.bundleID).inserted {
            apps.append(App(bundleID: a.bundleID, name: a.name, running: running.contains(a.bundleID),
                            isFavourite: favourite.contains(a.bundleID)))
        }
        for w in input.windows where seen.insert(w.bundleID).inserted {
            apps.append(App(bundleID: w.bundleID, name: w.appName, running: true, isFavourite: favourite.contains(w.bundleID)))
        }
        let byName: (App, App) -> Bool = {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.bundleID < $1.bundleID : order == .orderedAscending
        }
        switch input.appOrder {
        case .name:
            return apps.sorted(by: byName)
        case .recent:
            // Only the apps used from here: Recent starts empty and fills as apps are opened.
            return apps.filter { input.recents[$0.bundleID] != nil }.sorted { a, b in
                let x = input.recents[a.bundleID]!, y = input.recents[b.bundleID]!
                return x == y ? byName(a, b) : x > y
            }
        }
    }

    // MARK: Search

    /// Case and accents ignored, so "cafe" finds "Café".
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// 0: a name, or a word in it, starts with the query; 1: a name contains it; nil: no match.
    static func rank(_ texts: [String], _ q: String) -> Int? {
        var best: Int?
        for text in texts where !text.isEmpty {
            let t = fold(text)
            if t.hasPrefix(q) || words(t).contains(where: { $0.hasPrefix(q) }) { return 0 }
            if t.contains(q) { best = 1 }
        }
        return best
    }

    private static func words(_ t: String) -> [Substring] {
        t.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }

    private static func ranked<T>(_ items: [T], _ q: String, _ texts: (T) -> [String]) -> [T] {
        let scored = items.enumerated().compactMap { i, item in rank(texts(item), q).map { (r: $0, i: i, item: item) } }
        return scored.sorted { ($0.r, $0.i) < ($1.r, $1.i) }.map(\.item)
    }
}
