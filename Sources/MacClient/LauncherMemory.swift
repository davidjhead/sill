import Foundation
import Combine

/// What the launcher remembers of each Mac it has been connected to, in UserDefaults by Mac ID: its
/// favourite apps (a right-click's Add to Favourites, in the order added) and when each app was last
/// used from here (a launch from the launcher, or a window of the app taking the keyboard), for All
/// Apps' Recent order. The order itself is one for every Mac. Main thread.
final class LauncherMemory: ObservableObject {
    static let shared = LauncherMemory()

    @Published private(set) var favourites: [String] = []
    @Published private(set) var recents: [String: Double] = [:]
    @Published var appOrder: LauncherModel.AppOrder {
        didSet { UserDefaults.standard.set(appOrder.rawValue, forKey: "launcher.appOrder") }
    }
    private var mac: String?

    private init() {
        appOrder = UserDefaults.standard.string(forKey: "launcher.appOrder").flatMap(LauncherModel.AppOrder.init) ?? .name
    }

    /// The Mac this session is with: its favourites and recents come in.
    func use(mac: String?) {
        guard mac != self.mac else { return }
        self.mac = mac
        favourites = mac.flatMap { UserDefaults.standard.stringArray(forKey: key("favourites", $0)) } ?? []
        recents = mac.flatMap { UserDefaults.standard.dictionary(forKey: key("recents", $0)) as? [String: Double] } ?? [:]
    }

    func toggleFavourite(_ bundleID: String) {
        guard let mac else { return }
        favourites = LauncherModel.toggled(favourites, bundleID)
        UserDefaults.standard.set(favourites, forKey: key("favourites", mac))
    }

    /// `bundleID` used from here now. The last 200 are kept.
    func used(_ bundleID: String) {
        guard let mac, !bundleID.isEmpty else { return }
        recents[bundleID] = Date().timeIntervalSince1970
        if recents.count > 200 {
            for (id, _) in recents.sorted(by: { $0.value < $1.value }).prefix(recents.count - 200) { recents[id] = nil }
        }
        UserDefaults.standard.set(recents, forKey: key("recents", mac))
    }

    private func key(_ what: String, _ mac: String) -> String { "launcher.\(what).\(mac)" }
}
