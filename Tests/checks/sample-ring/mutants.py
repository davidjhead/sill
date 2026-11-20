"""Mutants of the Viewer's SampleRing.swift: each changes it in one place, is compiled with the check by
build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/MacClient/SampleRing.swift")
MUTANTS = [
    ("plays at once", "if !playing, count >= 40 * perMs { playing = true }", "if !playing, count >= 0 { playing = true }"),
    ("plays late", "if !playing, count >= 40 * perMs { playing = true }", "if !playing, count > 40 * perMs { playing = true }"),
    ("never catches up", "if count > 150 * perMs {", "if count > 1500 * perMs {"),
    ("catches up at 150 ms", "if count > 150 * perMs {", "if count >= 150 * perMs {"),
    ("keeps the oldest on catching up", "readAt = (readAt + count - keep) % size", "readAt = readAt % size"),
    ("keeps half a frame", "let keep = 60 * perMs - (60 * perMs) % channels", "let keep = 60 * perMs + 1"),
    ("no wrap on write", "if writeAt == size { writeAt = 0 }", "if writeAt == size + 1 { writeAt = 0 }"),
    ("overrun keeps the oldest", "if count > size { readAt = (readAt + count - size) % size; count = size }", "if count > size { count = size }"),
    ("dry keeps playing", "        } else if playing {\n            playing = false\n        }", "        }"),
    ("peeks the wrong channel", "return storage[(readAt + channel) % storage.count]", "return storage[readAt % storage.count]"),
    ("advances a sample, not a frame", "readAt = (readAt + channels) % storage.count", "readAt = (readAt + 1) % storage.count"),
    ("other channels played", "guard playing, count >= channels, channel < channels else { return 0 }", "guard playing, count >= channels else { return 0 }"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "SampleRing.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, f"SampleRing.swift={mf}"], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        try:
            r = subprocess.run([exe], capture_output=True, text=True, timeout=60)
            code, out = r.returncode, r.stdout
        except subprocess.TimeoutExpired:
            code, out = 1, "FAIL: timed out"
        failed = [l for l in out.splitlines() if l.startswith("FAIL")]
        if code != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit status {code}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
