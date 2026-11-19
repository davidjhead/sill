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
    ("windowed apps not installed left out", "            apps.append(App(bundleID: w.bundleID, name: w.appName, running: true))\n", ""),
    ("running never marked", "running: running.contains(a.bundleID)", "running: false"),
    ("apps in the host's order", "        return apps.sorted {", "        return apps; _ = apps.sorted {"),
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
