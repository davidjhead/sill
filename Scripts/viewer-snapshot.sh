#!/bin/bash
# Scripts/viewer-snapshot.sh [--push] [--no-tests]: a test build of Sill Viewer that can be rolled back to.
# From a clean, committed tree: runs Scripts/viewer-test.sh (the builds, the checks and every harness
# flow; a failure stops here, nothing zipped or tagged; --no-tests skips it), builds .build/Sill Viewer.app (make-client-app.sh, which stamps the
# commit into About), keeps a zip of it in SILL_VIEWER_BUILDS (~/SillViewerBuilds), named by version,
# build number and commit, and tags the commit viewer-<version>-b<build>. --push pushes the branch and
# that tag. Rolling back: unzip the previous zip from that folder (seconds, no build), or
# `git revert <commit>` and snapshot again; `git checkout <tag>` rebuilds any snapshot exactly.
set -euo pipefail
cd "$(dirname "$0")/.."
push=0
tests=1
for a in "$@"; do
    case "$a" in
        --push) push=1 ;;
        --no-tests) tests=0 ;;
        *) echo "usage: $0 [--push] [--no-tests]" >&2; exit 2 ;;
    esac
done
if ! git diff --quiet HEAD -- Sources iOSClient Packaging Package.swift Scripts design; then
    echo "uncommitted changes: commit first, so the snapshot names exactly what it holds" >&2; exit 1
fi
if [ "$tests" = 1 ]; then
    Scripts/viewer-test.sh || { echo "tests failed: no snapshot (fix, commit, and run this again)" >&2; exit 1; }
fi
Scripts/make-client-app.sh
app=".build/Sill Viewer.app"
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$app/Contents/Info.plist")
commit=$(git rev-parse --short=7 HEAD)
dir="${SILL_VIEWER_BUILDS:-$HOME/SillViewerBuilds}"
mkdir -p "$dir"
zip="$dir/Sill Viewer $version ($build) $commit.zip"
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
tag="viewer-$version-b$build"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    [ "$(git rev-list -n1 "$tag")" = "$(git rev-parse HEAD)" ] || { echo "tag $tag names another commit" >&2; exit 1; }
else
    git tag -a "$tag" -m "Sill Viewer $version ($build), $commit"
fi
echo "Snapshot: $zip"
echo "Tag:      $tag"
if [ "$push" = 1 ]; then
    git push
    git push origin "refs/tags/$tag"
fi
