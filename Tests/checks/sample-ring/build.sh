#!/bin/bash
# build.sh WORKTREE OUT [SampleRing.swift=replacement]: the Viewer's SampleRing with the check.
WT=$1; OUT=$2; shift 2; T=$(mktemp -d)
src="$WT/Sources/MacClient/SampleRing.swift"
for o in "$@"; do [ "${o%%=*}" = "SampleRing.swift" ] && src="${o#*=}"; done
cp "$src" "$T/SampleRing.swift"
cp "$(dirname "$0")/main.swift" "$T/main.swift"
swiftc -O "$T"/*.swift -o "$OUT" 2>&1 | grep -E "error"; rm -rf "$T"
