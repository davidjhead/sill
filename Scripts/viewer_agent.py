#!/usr/bin/env python3
"""TEST ONLY: an agent drives Sill Viewer against a test host on this Mac, headless.

    Scripts/viewer_agent.py start OUT [--locked] [--displays] [--screen] [--port-file]
    Scripts/viewer_agent.py send OUT <command…>        one command, its answer as JSON
    Scripts/viewer_agent.py run OUT FLOW [FLOW…]       start, each flow's steps and expects, stop
    Scripts/viewer_agent.py stop OUT

`start` runs a synthetic SillHost (.build/release/SillHost: loopback alone, the software encoder, no
router, no screen recording unless --screen) and a debug Sill Viewer (.build/debug/SillClient, its own
defaults domain `SillClient`, wiped first) with `-SillConnect 127.0.0.1:PORT -SillAgent OUT/agent`
(Sources/MacClient/AgentHarness.swift). No window of the Viewer shows and it takes no focus. A
synthetic host opens no app it is asked to launch and posts no input. Logs: OUT/host.log, OUT/viewer.log.

--locked: the host's screen reads locked until `send OUT unlock` (SILL_TEST_LOCKED_FILE).
--displays: two Desktop stops, as a Mac with a second display (SILL_TEST_DISPLAYS).
--screen: the host lists this Mac's real windows (asks macOS for screen recording; off by default).

The Viewer's commands are AgentHarness's (state, tree, press, menu, type, key, launcher, snap, wait,
quit); `send OUT unlock|lock` writes the host's lock file. A flow file has one step a line:

    # a comment
    wait apps 20
    press Notes                          any command
    expect counts.apps > 0               a path into `state`, then ==, !=, >, <, contains, !contains
    expect launcher.favourites contains Notes
    snap OUT/after-fav.png               a relative path is under OUT

`run` prints each step and PASS or FAIL for each expect, and exits 1 when one failed.
Needs `swift build` (debug) and `swift build -c release`.
"""
import json, os, re, signal, subprocess, sys, time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
HOST = os.path.join(ROOT, ".build/release/SillHost")
VIEWER = os.path.join(ROOT, ".build/debug/SillClient")
BASE_ENV = {"SILL_TEST_LOOPBACK": "1", "SILL_TEST_SOFTWARE_ENCODER": "1", "SILL_TEST_NO_ROUTER": "1",
            "SILL_TEST_LOCK_IGNORE_MAC": "1"}
DISPLAYS = "Built-in Retina Display:1512x982@2:120:0,0;DELL U2723QE:2560x1440@1:60:1512,0"


def session(out):
    with open(os.path.join(out, "session.json")) as f: return json.load(f)


def alive(pid):
    try: os.kill(pid, 0); return True
    except OSError: return False


def start(out, flags):
    for path in (HOST, VIEWER):
        if not os.path.exists(path): raise SystemExit(f"missing {path}: swift build and swift build -c release first")
    os.makedirs(out, exist_ok=True)
    if os.path.exists(os.path.join(out, "session.json")) and alive(session(out)["viewer"]):
        raise SystemExit(f"{out}: a session runs; stop it first")
    env = dict(os.environ); env.update(BASE_ENV)
    if "--screen" not in flags: env["SILL_TEST_NO_SCREEN"] = "1"
    lock = os.path.join(out, "host.lock")
    with open(lock, "w") as f: f.write("1" if "--locked" in flags else "0")
    env["SILL_TEST_LOCKED_FILE"] = lock
    if "--displays" in flags: env["SILL_TEST_DISPLAYS"] = DISPLAYS
    host = subprocess.Popen(["nice", "-n", "10", HOST, "--synthetic"], stdout=open(os.path.join(out, "host.log"), "w"),
                            stderr=subprocess.STDOUT, env=env, start_new_session=True)
    port = None
    for _ in range(100):
        time.sleep(0.1)
        r = subprocess.run(["lsof", "-nP", "-a", "-p", str(host.pid), "-iTCP", "-sTCP:LISTEN"], capture_output=True, text=True)
        if re.findall(r"(\*|\[::\]|0\.0\.0\.0):(\d+) \(LISTEN\)", r.stdout):
            os.killpg(host.pid, signal.SIGTERM); raise SystemExit("the host listens beyond loopback: stopped")
        ports = re.findall(r"127\.0\.0\.1:(\d+) \(LISTEN\)", r.stdout)
        if ports: port = ports[0]; break
    if port is None:
        os.killpg(host.pid, signal.SIGTERM); raise SystemExit("the host has no listening port (OUT/host.log)")
    agent = os.path.join(out, "agent")
    if os.path.isdir(agent):
        for n in os.listdir(agent): os.remove(os.path.join(agent, n))
    subprocess.run(["defaults", "delete", "SillClient"], capture_output=True)   # the harness's own domain, never the app's
    viewer = subprocess.Popen([VIEWER, "-SillConnect", f"127.0.0.1:{port}", "-SillAgent", agent],
                              stdout=open(os.path.join(out, "viewer.log"), "w"), stderr=subprocess.STDOUT, start_new_session=True)
    with open(os.path.join(out, "session.json"), "w") as f:
        json.dump({"host": host.pid, "viewer": viewer.pid, "port": port, "agent": agent, "lock": lock}, f)
    for _ in range(150):
        if os.path.exists(os.path.join(agent, "ready")): break
        if viewer.poll() is not None: stop(out); raise SystemExit("the Viewer quit (OUT/viewer.log)")
        time.sleep(0.1)
    else:
        stop(out); raise SystemExit("the Viewer's harness did not start (OUT/viewer.log)")
    print(f"started: host {host.pid} on 127.0.0.1:{port}, viewer {viewer.pid}")


def send(out, line, timeout=60):
    s = session(out)
    if line in ("lock", "unlock"):
        with open(s["lock"], "w") as f: f.write("1" if line == "lock" else "0")
        return {"ok": True}
    if not alive(s["viewer"]): return {"ok": False, "error": "the Viewer is not running (OUT/viewer.log)"}
    n = len([x for x in os.listdir(s["agent"]) if x.endswith(".cmd")]) + 1
    name = f"{n:05d}"
    tmp = os.path.join(s["agent"], name + ".tmp")
    with open(tmp, "w") as f: f.write(line + "\n")
    os.rename(tmp, os.path.join(s["agent"], name + ".cmd"))
    reply = os.path.join(s["agent"], name + ".json")
    end = time.time() + timeout
    while time.time() < end:
        if os.path.exists(reply):
            with open(reply) as f: return json.load(f)
        if not alive(s["viewer"]): return {"ok": False, "error": "the Viewer quit (OUT/viewer.log)"}
        time.sleep(0.05)
    return {"ok": False, "error": f"no answer in {timeout} s"}


def stop(out):
    try: s = session(out)
    except FileNotFoundError: return
    for pid in (s["viewer"], s["host"]):
        try: os.killpg(pid, signal.SIGTERM)
        except OSError: pass
    for pid in (s["viewer"], s["host"]):
        for _ in range(30):
            if not alive(pid): break
            time.sleep(0.1)
        else:
            try: os.killpg(pid, signal.SIGKILL)
            except OSError: pass
    subprocess.run(["defaults", "delete", "SillClient"], capture_output=True)
    os.remove(os.path.join(out, "session.json"))


def lookup(state, path):
    v = state
    for part in path.split("."):
        if isinstance(v, list) and part.isdigit(): v = v[int(part)] if int(part) < len(v) else None
        elif isinstance(v, dict): v = v.get(part)
        else: return None
    return v


def check(state, path, op, want):
    got = lookup(state, path)
    def num(x):
        try: return float(x)
        except (TypeError, ValueError): return len(x) if isinstance(x, (list, str, dict)) else None
    if op == "contains": ok = isinstance(got, (list, str)) and want in got
    elif op == "!contains": ok = isinstance(got, (list, str)) and want not in got
    elif op in (">", "<"):
        a, b = num(got), num(want); ok = a is not None and b is not None and (a > b if op == ">" else a < b)
    else:
        same = str(got).lower() == want.lower() if isinstance(got, bool) else str(got) == want
        ok = same if op == "==" else not same
    return ok, got


def run(out, flows):
    failed = 0
    for flow in flows:
        lines = [l.strip() for l in open(flow)]
        flags = next((l.split()[1:] for l in lines if l.startswith("start-flags ")), [])
        print(f"== {flow}" + (f" ({' '.join(flags)})" if flags else ""))
        start(out, flags)
        try:
            for line in lines:
                if not line or line.startswith("#") or line.startswith("start-flags "): continue
                if line.startswith("expect "):
                    m = re.match(r"expect (\S+) (==|!=|>|<|contains|!contains) (.*)$", line)
                    if not m: print(f"  FAIL  {line}: not an expect"); failed += 1; continue
                    state = send(out, "state")
                    ok, got = check(state, *m.groups())
                    print(f"  {'PASS' if ok else 'FAIL'}  {line}" + ("" if ok else f"   (got {json.dumps(got)[:200]})"))
                    failed += not ok
                    continue
                words = line.split()
                if words[0] == "snap" and len(words) > 1 and not os.path.isabs(words[1]):
                    words[1] = os.path.join(os.path.abspath(out), words[1]); line = " ".join(words)
                answer = send(out, line)
                print(f"  {'ok  ' if answer.get('ok') else 'ERR '}  {line}" + ("" if answer.get("ok") else f"   ({answer.get('error')})"))
                if not answer.get("ok"): failed += 1
        finally:
            stop(out)
    print("All passed." if not failed else f"{failed} failed.")
    return 1 if failed else 0


def main(argv):
    if len(argv) < 3 or argv[1] not in ("start", "send", "run", "stop"): print(__doc__); return 2
    cmd, out = argv[1], argv[2]
    if cmd == "start": start(out, argv[3:]); return 0
    if cmd == "stop": stop(out); return 0
    if cmd == "run": return run(out, argv[3:])
    answer = send(out, " ".join(argv[3:]))
    print(json.dumps(answer, indent=2, sort_keys=True))
    return 0 if answer.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
