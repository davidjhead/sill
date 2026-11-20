#!/bin/bash
# Scripts/viewer-test.sh: every test of Sill Viewer, as each build runs them (viewer-snapshot.sh runs it
# before it zips or tags anything): the debug and release builds, the pure checks that cover the Viewer,
# and every flow in Scripts/viewer-flows driven headless against a synthetic host (viewer_agent.py: no
# window shows, nothing reaches a real Mac). Exits 1 when anything fails; the flows' snapshots and logs
# are kept in SILL_VIEWER_TEST_OUT (.build/viewer-test). About 2 minutes.
set -uo pipefail
cd "$(dirname "$0")/.."
out="${SILL_VIEWER_TEST_OUT:-.build/viewer-test}"
rm -rf "$out"; mkdir -p "$out"
fail=0
step() { echo "== $1"; }
step "debug build (the harness's Viewer)"
swift build --product SillClient > "$out/build-debug.log" 2>&1 || { echo "FAIL: debug build ($out/build-debug.log)"; exit 1; }
step "release build (the host the harness runs, and the app)"
swift build -c release > "$out/build-release.log" 2>&1 || { echo "FAIL: release build ($out/build-release.log)"; exit 1; }
step "pure checks"
Tests/checks/run-all.sh launcher sample-ring main-router display-wake repo-rules 2>&1 | tee "$out/checks.log" | tail -6
grep -q "^All passed" "$out/checks.log" || fail=1
step "flows"
Scripts/viewer_agent.py run "$out" Scripts/viewer-flows/*.flow > "$out/flows.log" 2>&1 || fail=1
grep -E "^==|FAIL|ERR" "$out/flows.log"
tail -1 "$out/flows.log"
pgrep -f "debug/SillClient -SillConnect" >/dev/null && { echo "FAIL: a harness Viewer was left running"; fail=1; }
[ "$fail" = 0 ] && echo "Viewer tests: all passed." || echo "Viewer tests: FAILED (logs and snapshots in $out)"
exit $fail
