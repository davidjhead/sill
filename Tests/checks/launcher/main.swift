import Foundation

var checks = 0, failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}

func win(_ id: UInt32, _ title: String, _ app: String, _ bundle: String) -> WindowInfo {
    WindowInfo(id: id, title: title, appName: app, bundleID: bundle, width: 800, height: 600)
}
let safari = win(11, "Sill on GitHub", "Safari", "com.apple.Safari")
let safari2 = win(12, "", "Safari", "com.apple.Safari")
let xcode = win(21, "Sill.xcodeproj", "Xcode", "com.apple.dt.Xcode")
let helper = win(31, "Untitled", "Helper Tool", "com.example.helper")   // has a window, not installed
let installed = [AppInfo(name: "Xcode", bundleID: "com.apple.dt.Xcode"), AppInfo(name: "Safari", bundleID: "com.apple.Safari"),
                 AppInfo(name: "Café Menu", bundleID: "com.example.cafe"), AppInfo(name: "app Store", bundleID: "com.apple.AppStore"),
                 AppInfo(name: "Safari", bundleID: "com.apple.Safari"),   // listed twice by the host: once here
                 AppInfo(name: "Calendar", bundleID: "com.apple.iCal"), AppInfo(name: "Notes", bundleID: "com.apple.Notes")]
let base = LauncherModel.Input(windows: [safari, xcode, safari2, helper], apps: installed, open: [.window(21)])

// Sections, no search.
do {
    let m = LauncherModel.make(base)
    check(m.desktops == [.init(source: .desktop, name: "Desktop", detail: nil, isOpen: false)],
          "one Desktop, unnamed, from a host without displays or stops: \(m.desktops)")
    check(m.windows.map(\.id) == [11, 21, 12, 31], "windows keep the bar's order: \(m.windows.map(\.id))")
    check(m.windows.first { $0.id == 12 }?.title == "Safari", "an untitled window goes by its app's name")
    check(m.windows.filter(\.isOpen).map(\.id) == [21], "only the window open here is marked open: \(m.windows.filter(\.isOpen).map(\.id))")
    check(m.apps.map(\.name) == ["app Store", "Café Menu", "Calendar", "Helper Tool", "Notes", "Safari", "Xcode"],
          "apps A to Z, case ignored, a windowed app not installed added, a twice-listed app once: \(m.apps.map(\.name))")
    check(Set(m.apps.filter(\.running).map(\.bundleID)) == ["com.apple.Safari", "com.apple.dt.Xcode", "com.example.helper"],
          "running = has a window: \(m.apps.filter(\.running).map(\.name))")
    check(m.firstChoice == .app("com.apple.AppStore"), "Return with no search opens the first app: \(String(describing: m.firstChoice))")
    check(!m.isEmpty, "a model with sections is not empty")
}

// The Desktop: open, and named after its stop (#91) when the host has two or more.
do {
    var i = base
    i.open = [.desktop]
    i.desktopNames = ["Built-in Retina Display", "DELL U2723QE"]; i.desktopCurrent = 2
    let m = LauncherModel.make(i)
    check(m.desktops == [.init(source: .desktop, name: "Desktop", detail: "DELL U2723QE · 2 of 2", isOpen: true)],
          "the Desktop names the stop it shows and is marked open: \(m.desktops)")
    i.desktopNames = ["Built-in Retina Display"]; i.desktopCurrent = 1
    check(LauncherModel.make(i).desktops.first?.detail == nil, "one stop: no detail")
    i.desktopNames = ["A", "B"]; i.desktopCurrent = 3
    check(LauncherModel.make(i).desktops.first?.detail == nil, "a stop out of range: no detail")
    i.desktopNames = ["A", "  "]; i.desktopCurrent = 2
    check(LauncherModel.make(i).desktops.first?.detail == "Display 2 · 2 of 2", "a blank name: the display's number")
}

// A #66 host's displays: each a Desktop window of its own.
do {
    var i = base
    i.hostDisplays = [DisplayInfo(id: 1, name: "Built-in", width: 1512, height: 982, main: true),
                      DisplayInfo(id: 7, name: "DELL U2723QE", width: 2560, height: 1440)]
    i.open = [.window(DesktopWindow.id(display: 7))]
    let m = LauncherModel.make(i)
    check(m.desktops.map(\.source) == [.window(DesktopWindow.id(display: 1)), .window(DesktopWindow.id(display: 7))],
          "one Desktop per display, as its tagged window: \(m.desktops.map(\.source))")
    check(m.desktops.map(\.name) == ["Built-in", "DELL U2723QE"], "several displays go by their names")
    check(m.desktops.map(\.detail) == ["Main display", nil], "the main one says so")
    check(m.desktops.map(\.isOpen) == [false, true], "the open one is marked")
    i.hostDisplays = [i.hostDisplays[1]]
    let one = LauncherModel.make(i).desktops
    check(one.count == 1 && one[0].name == "Desktop" && one[0].detail == "DELL U2723QE", "one display: Desktop, its name below: \(one)")
}

// Search.
do {
    let m = LauncherModel.make(base, query: "  SAF ")
    check(m.apps.map(\.name) == ["Safari"], "a search trims and ignores case: \(m.apps.map(\.name))")
    check(m.windows.map(\.id) == [11, 12], "windows match by their app's name too: \(m.windows.map(\.id))")
    check(m.desktops.isEmpty, "the Desktop goes when it does not match")
    check(m.firstChoice == .app("com.apple.Safari"), "Return opens the first matching app")

    let cafe = LauncherModel.make(base, query: "cafe")
    check(cafe.apps.map(\.name) == ["Café Menu"], "accents ignored: \(cafe.apps.map(\.name))")

    let menu = LauncherModel.make(base, query: "menu")
    check(menu.apps.map(\.name) == ["Café Menu"], "a word inside a name matches by its start: \(menu.apps.map(\.name))")

    let ar = LauncherModel.make(base, query: "ar")
    check(ar.apps.map(\.name) == ["Calendar", "Safari"], "contains matches when no prefix does, A to Z: \(ar.apps.map(\.name))")

    let a = LauncherModel.make(base, query: "a")
    check(a.apps.first?.name == "app Store", "a prefix match comes first: \(a.apps.map(\.name))")
    check(a.apps.map(\.name) == ["app Store", "Café Menu", "Calendar", "Safari"],
          "then everything containing it, in order: \(a.apps.map(\.name))")

    let s = LauncherModel.make(base, query: "s")
    check(s.apps.map(\.name) == ["app Store", "Safari", "Notes"],
          "word and name starts before a name that only contains it, though it sorts earlier: \(s.apps.map(\.name))")

    let title = LauncherModel.make(base, query: "github")
    check(title.windows.map(\.id) == [11] && title.apps.isEmpty, "a window title matches; its app does not by it: \(title.windows.map(\.id))")
    check(title.firstChoice == .window(11), "Return opens the first window when no app matches")

    var i = base
    i.desktopNames = ["Built-in Retina Display", "DELL U2723QE"]; i.desktopCurrent = 2
    let dell = LauncherModel.make(i, query: "dell")
    check(dell.desktops.count == 1 && dell.apps.isEmpty && dell.windows.isEmpty, "a display name finds the Desktop")
    check(dell.firstChoice == .desktop(.desktop), "Return opens the Desktop when it is all that matches")

    let none = LauncherModel.make(base, query: "zzz")
    check(none.isEmpty && none.firstChoice == nil, "no match: empty, and Return opens nothing")

    let blank = LauncherModel.make(base, query: "   ")
    check(blank == LauncherModel.make(base), "a blank search is no search")
}

// Favourites: in the order added, only apps the other Mac lists, each once; searched like the rest.
do {
    var i = base
    i.favourites = ["com.apple.Safari", "com.gone.app", "com.apple.Notes", "com.apple.Safari"]
    let m = LauncherModel.make(i)
    check(m.favourites.map(\.name) == ["Safari", "Notes"], "favourites in the order added, unlisted and repeated left out: \(m.favourites.map(\.name))")
    check(m.apps.filter(\.isFavourite).map(\.name) == ["Notes", "Safari"], "All Apps marks the favourites: \(m.apps.filter(\.isFavourite).map(\.name))")
    check(m.apps.count == 7, "a favourite stays in All Apps too")
    check(m.favourites.first { $0.name == "Safari" }?.running == true, "a favourite says when it runs")
    check(LauncherModel.make(i, query: "saf").favourites.map(\.name) == ["Safari"], "a search keeps the favourites that match")
    check(LauncherModel.make(base).favourites.isEmpty, "no favourites: an empty section")
    var only = LauncherModel.Input(); only.apps = [AppInfo(name: "Notes", bundleID: "n")]; only.favourites = ["n"]
    check(!LauncherModel.make(only, query: "no").isEmpty, "a model with only a favourite and its app is not empty")
}

// Toggling a favourite: added at the end, removed from wherever it is.
check(LauncherModel.toggled(["a", "b"], "c") == ["a", "b", "c"], "an app added goes last")
check(LauncherModel.toggled(["a", "b", "c"], "b") == ["a", "c"], "an app removed leaves the rest in order")

// Recent: only what was used from here (apps, and Desktops by their recentKey), latest first, a tie A to Z;
// empty until something is; a search still looks through every app; nothing of it in the A to Z order.
do {
    var i = base
    i.appOrder = .recent
    check(LauncherModel.make(i).apps.isEmpty && LauncherModel.make(i).recent.isEmpty, "Recent starts empty")
    i.recents = ["com.apple.Notes": 500, "com.apple.dt.Xcode": 300, "com.apple.Safari": 300,
                 LauncherModel.recentKey(.desktop): 400]   // the host lists Xcode before Safari
    let m = LauncherModel.make(i)
    check(m.apps.map(\.name) == ["Notes", "Safari", "Xcode"], "only the used apps, latest first, a tie A to Z: \(m.apps.map(\.name))")
    check(m.recent.map(\.name) == ["Notes", "Desktop", "Safari", "Xcode"], "Recent's list has the Desktop by when: \(m.recent.map(\.name))")
    if case .desktop(let d)? = m.recent.dropFirst().first { check(d.source == .desktop, "the Desktop's tile opens the Desktop") }
    else { check(false, "the second of Recent is the Desktop") }
    check(LauncherModel.make(i, query: "a").apps.first?.name == "app Store", "a search in Recent looks through every app")
    check(LauncherModel.make(i, query: "desk").recent.map(\.name) == ["Desktop"], "a search narrows Recent's list too")
    check(LauncherModel.recentKey(.window(7)) == "desktop:7" && LauncherModel.recentKey(.desktop) == "desktop", "a display's Desktop has a key of its own")
    i.appOrder = .name
    check(LauncherModel.make(i).apps.map(\.name).first == "app Store", "A to Z ignores when apps were used")
    check(LauncherModel.make(i).recent.isEmpty, "no Recent list in the A to Z order")
}

// The ranks themselves.
check(LauncherModel.rank(["Visual Studio Code"], "stu") == 0, "a word's start ranks 0")
check(LauncherModel.rank(["Visual Studio Code"], "udi") == 1, "inside a word ranks 1")
check(LauncherModel.rank(["Visual Studio Code"], "xyz") == nil, "no match: nil")
check(LauncherModel.rank(["", "Notes"], "no") == 0, "an empty text is skipped")
check(LauncherModel.rank(["Window 2", "Notes"], "2") == 0, "a number starts a word")
check(LauncherModel.rank(["iTerm2"], "term") == 1, "a word runs across a change of case")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
