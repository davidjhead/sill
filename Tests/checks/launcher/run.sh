#!/bin/bash
# The Mac client's launcher model (Sources/MacClient/LauncherModel.swift): the Desktops (one per display
# of a #66 host, else the one Desktop named after its stop), the windows by title, every app A to Z with
# the running ones marked and windowed apps not installed added, and the search: case and accents
# ignored, name and word prefixes before contains, Return's first choice.
#   Tests/checks/launcher/run.sh             compile and run the check
#   Tests/checks/launcher/run.sh --mutants   one-line mutants of LauncherModel.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
