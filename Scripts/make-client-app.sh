#!/bin/bash
# Sill Viewer, the Mac client (Sources/MacClient): .build/Sill Viewer.app, from `swift build`.
#   Scripts/make-client-app.sh             release build, signed with your Developer ID
#   Scripts/make-client-app.sh --debug     debug build (DEBUG launch arguments such as -SillConnect)
#   Scripts/make-client-app.sh --notarize  …then notarized and stapled (.build/Sill Viewer.zip too)
#   Scripts/make-client-app.sh --open      …and open it
# Signing: SILL_SIGN_IDENTITY (a name or SHA-1), else the first Developer ID Application identity,
# else the first Apple Development one, else ad hoc. A real identity keeps the login keychain's
# device key and the privacy grants (Local Network, Accessibility) across rebuilds and copies to
# another Mac: both name the signature's designated requirement, which an ad hoc signature changes
# with every build. Notarizing uses the notarytool profile SILL_NOTARY_PROFILE (sill-notary). The icon
# is design/ViewerIcon.svg, compiled as Scripts/make-app.sh compiles Sill's (Quick Look's render as the
# one layer of an Icon Composer document, then actool), cached in .build/viewer-icon.
set -euo pipefail
cd "$(dirname "$0")/.."
config=release; open_after=0; notarize=0
for a in "$@"; do
    case "$a" in
        --debug) config=debug ;;
        --open) open_after=1 ;;
        --notarize) notarize=1 ;;
        *) echo "usage: $0 [--debug] [--notarize] [--open]" >&2; exit 2 ;;
    esac
done
swift build -c "$config" --product SillClient
swift build -c "$config" --product SillDockProxy
app=".build/Sill Viewer.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp ".build/$config/SillClient" "$app/Contents/MacOS/SillClient"
cp Packaging/Client-Info.plist "$app/Contents/Info.plist"
# The Dock icon helper (Sources/SillDockProxy), copied and renamed per remote app at run time.
helper="$app/Contents/Helpers/SillDockProxy.app"
mkdir -p "$helper/Contents/MacOS"
cp ".build/$config/SillDockProxy" "$helper/Contents/MacOS/SillDockProxy"
cat > "$helper/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>SillDockProxy</string>
	<key>CFBundleIdentifier</key><string>me.saffer.sill.client.dock</string>
	<key>CFBundleName</key><string>Sill Dock Icon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" "$app/Contents/Info.plist"
# The commit it was built from (About shows it), "+changes" when the tree had uncommitted edits.
commit=$(git rev-parse --short=7 HEAD 2>/dev/null || echo unknown)
git diff --quiet HEAD -- Sources iOSClient Packaging Package.swift 2>/dev/null || commit="$commit+changes"
/usr/libexec/PlistBuddy -c "Add :SillCommit string $commit" "$app/Contents/Info.plist"
# The icon: design/ViewerIcon.svg, as make-app.sh does Sill's (its comment says why actool, not iconutil).
icon_out="$PWD/.build/viewer-icon"   # absolute: actool resolves relative paths in its helper's directory
if [ ! -f "$icon_out/compiled/Assets.car" ] || [ design/ViewerIcon.svg -nt "$icon_out/compiled/Assets.car" ] \
   || [ "$0" -nt "$icon_out/compiled/Assets.car" ]; then
    rm -rf "$icon_out"; doc="$icon_out/AppIcon.icon"; mkdir -p "$icon_out/compiled" "$doc/Assets"
    qlmanage -t -s 1024 -o "$icon_out" "$PWD/design/ViewerIcon.svg" >/dev/null 2>&1 || true
    if mv "$icon_out/ViewerIcon.svg.png" "$doc/Assets/Viewer.png" 2>/dev/null; then
        cat > "$doc/icon.json" <<'JSON'
{
  "fill" : { "solid" : "srgb:0.00000,0.00000,0.00000,1.00000" },
  "groups" : [ { "layers" : [ { "image-name" : "Viewer.png", "name" : "Viewer" } ] } ],
  "supported-platforms" : { "squares" : [ "macOS" ] }
}
JSON
        xcrun actool --compile "$icon_out/compiled" --platform macosx --minimum-deployment-target 14.0 \
            --app-icon AppIcon --output-partial-info-plist "$icon_out/partial.plist" "$doc" >/dev/null \
            || echo "warning: actool could not compile the icon; Sill Viewer gets the generic icon" >&2
    else
        echo "warning: Quick Look did not render design/ViewerIcon.svg; Sill Viewer gets the generic icon" >&2
    fi
fi
cp "$icon_out"/compiled/* "$app/Contents/Resources/" 2>/dev/null || true
ids="$(security find-identity -v -p codesigning 2>/dev/null || true)"
identity="${SILL_SIGN_IDENTITY:-$(echo "$ids" | awk '/"Developer ID Application: / { print $2; exit }')}"
[ -n "$identity" ] || identity="$(echo "$ids" | awk '/"Apple Development: / { print $2; exit }')"
[ -n "$identity" ] || { identity="-"; echo "warning: no signing identity; signing ad hoc" >&2; }
# The helper first (a nested bundle is sealed into its parent's signature), then the app.
if [ "$identity" = "-" ]; then
    codesign --force --options runtime --timestamp=none --sign - "$helper"
    codesign --force --options runtime --timestamp=none --sign - "$app"
else
    codesign --force --options runtime --timestamp --sign "$identity" "$helper"
    codesign --force --options runtime --timestamp --sign "$identity" "$app"
fi
codesign --verify --strict "$app"
echo "Signed by: $(codesign -dv --verbose=2 "$app" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
if [ "$notarize" = 1 ]; then
    [ "$config" = release ] || { echo "error: --notarize is for the release build (a debug build carries test hooks)" >&2; exit 1; }
    profile="${SILL_NOTARY_PROFILE:-sill-notary}"
    zip=".build/Sill Viewer.zip"
    rm -f "$zip"; ditto -c -k --keepParent "$app" "$zip"
    xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
    xcrun stapler staple "$app"
    rm -f "$zip"; ditto -c -k --keepParent "$app" "$zip"
    spctl -a -vv -t exec "$app"
fi
echo "Built $app ($config, $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist"))"
[ "$open_after" = 1 ] && open "$app"
exit 0
