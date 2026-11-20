"""Mutants of the Mac client's LauncherModel.swift: each changes it in one place, is compiled with the
check by build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/MacClient/LauncherModel.swift")
MUTANTS = [
    ("an untitled window stays untitled", "title: w.title.isEmpty ? w.appName : w.title", "title: w.title"),
    ("windows never marked open", "isOpen: input.open.contains(.window(w.id)))", "isOpen: false)"),
    ("the Desktop never marked open", "isOpen: input.open.contains(.desktop))]", "isOpen: false)]"),
    ("a display's Desktop never marked open", "                               isOpen: input.open.contains(source))", "                               isOpen: false)"),
    ("a twice-listed app twice", "for a in input.apps where seen.insert(a.bundleID).inserted {", "for a in input.apps { seen.insert(a.bundleID)"),
    ("windowed apps not installed left out", "            apps.append(App(bundleID: w.bundleID, name: w.appName, running: true, isFavourite: favourite.contains(w.bundleID),\n                            openHere: openHere.contains(w.bundleID)))\n", ""),
    ("running never marked", "running: running.contains(a.bundleID)", "running: false"),
    ("apps in the host's order", "            return apps.sorted(by: byName)", "            return apps"),
    ("favourites A to Z", "let favourites = input.favourites.compactMap {", "let favourites = input.favourites.sorted().compactMap {"),
    ("a favourite twice", "compactMap { id in seen.insert(id).inserted ? byID[id] : nil }", "compactMap { id in byID[id] }"),
    ("favourites never marked in All Apps", "isFavourite: favourite.contains(a.bundleID), openHere:", "isFavourite: false, openHere:"),
    ("favourites not searched", "favourites: ranked(all.favourites, q) { [$0.name] },", "favourites: all.favourites,"),
    ("a favourite added first", ": favourites + [bundleID]", ": [bundleID] + favourites"),
    ("a favourite never removed", "favourites.contains(bundleID) ? favourites.filter { $0 != bundleID }", "favourites.contains(bundleID) ? favourites"),
    ("recent oldest first", "return x == y ? byName(a, b) : x > y", "return x == y ? byName(a, b) : x < y"),
    ("a recent tie unsorted", "return x == y ? byName(a, b) : x > y", "return x > y"),
    ("the never used in Recent", "return apps.filter { input.recents[$0.bundleID] != nil }.sorted { a, b in\n                let x = input.recents[a.bundleID]!, y = input.recents[b.bundleID]!", "return apps.sorted { a, b in\n                let x = input.recents[a.bundleID] ?? 0, y = input.recents[b.bundleID] ?? 0"),
    ("no Desktop in Recent", "            + desktops.compactMap { d in recents[recentKey(d.source)].map { (t: $0, item: RecentItem.desktop(d)) } }\n", ""),
    ("Recent merged oldest first", "if a.t != b.t { return a.t > b.t }", "if a.t != b.t { return a.t < b.t }"),
    ("a search in Recent only through the used", "ranked(input.appOrder == .name ? all.apps : Self.apps(named(input)), q)", "ranked(all.apps, q)"),
    ("Recent's list not searched", "recent: ranked(all.recent, q) { [$0.name] })", "recent: all.recent)"),
    ("a Recent list in the A to Z order", "recent: input.appOrder == .recent ? recent(apps, desktops, input.recents) : [])", "recent: recent(apps, desktops, input.recents))"),
    ("favourites only from Recent's list", "let every = input.appOrder == .name ? apps : Self.apps(named(input))", "let every = apps"),
    ("untitled windows opened", "windows.filter { $0.bundleID == bundleID && !$0.title.isEmpty && $0.width >= 80", "windows.filter { $0.bundleID == bundleID && $0.width >= 80"),
    ("strips opened", "&& $0.width >= 80 && $0.height >= 150 }", "&& $0.width >= 80 }"),
    ("slivers opened", "&& $0.width >= 80 && $0.height >= 150 }", "&& $0.height >= 150 }"),
    ("another app's windows opened", "windows.filter { $0.bundleID == bundleID && !$0.title.isEmpty", "windows.filter { !$0.title.isEmpty"),
    ("open here never marked", "openHere: openHere.contains(a.bundleID)))", "openHere: false))"),
    ("open here for every running app", "let openHere = Set(input.windows.filter { input.open.contains(.window($0.id)) }.map(\\.bundleID))", "let openHere = Set(input.windows.map(\\.bundleID))"),
    ("one key for every Desktop", "case .window(let id): return \"desktop:\\(id)\"", "case .window: return \"desktop\""),
    ("one display named as many", "let many = input.hostDisplays.count > 1", "let many = true"),
    ("the main display not said", "d.main == true ? \"Main display\" : nil", "nil"),
    ("the stop not named", "        if let names = input.desktopNames, names.count > 1,", "        if let names = input.desktopNames, names.count > 99,"),
    ("a stop out of range named", "let n = input.desktopCurrent, (1...names.count).contains(n) {", "let n = input.desktopCurrent, n >= 1, n <= names.count + 1 {"),
    ("a blank name kept", "(name.isEmpty ? \"Display \\(n)\" : name)", "name"),
    ("the search not trimmed", "let q = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))", "let q = fold(query)"),
    ("case kept", "s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)", "s.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)"),
    ("accents kept", "s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)", "s.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)"),
    ("words never matched", "if t.hasPrefix(q) || words(t).contains(where: { $0.hasPrefix(q) }) { return 0 }", "if t.hasPrefix(q) { return 0 }"),
    ("contains never matched", "            if t.contains(q) { best = 1 }\n", ""),
    ("prefixes not first", "return scored.sorted { ($0.r, $0.i) < ($1.r, $1.i) }.map(\\.item)", "return scored.map(\\.item)"),
    ("windows not searched by their app", "ranked(all.windows, q) { [$0.title, $0.appName] }", "ranked(all.windows, q) { [$0.title] }"),
    ("displays not searched by name", "ranked(all.desktops, q) { [$0.name, $0.detail ?? \"\"] }", "ranked(all.desktops, q) { [$0.name] }"),
    ("Return prefers windows", "        if let a = apps.first { return .app(a.bundleID) }\n        if let w = windows.first { return .window(w.id) }", "        if let w = windows.first { return .window(w.id) }\n        if let a = apps.first { return .app(a.bundleID) }"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "LauncherModel.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, f"LauncherModel.swift={mf}"], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
