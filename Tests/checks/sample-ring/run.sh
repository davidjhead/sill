#!/bin/bash
# The Viewer's sound ring (Sources/MacClient/SampleRing.swift): samples in and out in order across the
# ring's end, playing from 40 ms, silence and a stop when dry, the oldest dropped past 150 ms down to 60.
#   Tests/checks/sample-ring/run.sh             compile and run the check
#   Tests/checks/sample-ring/run.sh --mutants   one-line mutants of SampleRing.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
