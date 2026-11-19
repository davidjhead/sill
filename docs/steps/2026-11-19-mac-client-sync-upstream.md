**The Mac client brought up to main as of 2026-11-19 (0.6.3), so it builds beside main's new iPhone and iPad features (2026-11-19, branch `mac-client-sync-upstream` from `mac-client-stage1`, main at 41e8cb8 before the merge).**

What: `upstream/main` (216 commits, 2026-11-12 to 2026-11-19: Picture in Picture #291, full screen #360, the Desktop's displays #91 with kind 47, off-console view #316, the one-click updater, auto-lock hold #230, the lean CLAUDE.md) merged into the Mac client branch (stage 1 of pull request #66, docs/mac-client-prd.md).

Decisions:
- Kinds: #66's 29–31 and 34–42 kept, main's 47 (`nextDisplay`) beside them; 33, 45 and 46 stay unknown to this build. display-wake's count is 46, pointer-control's table has all of them.
- `WindowList.desktopDisplay`: main's (an `Int`, the Desktop's stop, #91) keeps the name; #66's (a `UInt32` display ID, kind 40) is `pickedDisplay` here. The two Desktop-display designs are to be reconciled when #66's host side comes in (stage 2); until then main's host sends only its own.
- Shared StreamClient: Picture in Picture's state reaches the Mac client too, as `.off` for good. `sceneInFront` is the platform seam (UIKit's scene, or `NSApp.isActive` in MacPlatformShims.swift); `pictureActive` is main's, platform-neutral. The background notification goes through `ClientPlatform.didEnterBackground` as before, now setting `appInBackground` and `runningChanged()`. The Desktop step's VoiceOver line goes through a new `ClientPlatform.announce`.
- Mac stand-ins (MacPlatformShims.swift): `PictureInPicture` (unsupported), `PictureInPictureHub`, `DeviceIdleTimer` and `AudioOutput.setPictureInPicture` as no-ops; `HEVCDisplayView.setFrozen` a no-op (the Mac's picture never freezes). `PictureInPicturePolicy.swift` and `DeviceIdlePolicy.swift` are symlinked into Sources/MacClient/Shared, both Foundation only.
- READMEs for #66's `mac-keys` and `main-router` checks, which main's repo-rules now asks of every check folder.

Verified: `swift build` (every target), `Tests/checks/run-all.sh`: every check passes.

Untested: the iOS app build (this Mac's Xcode simulator plug-in fails; CI will say), and the Mac client against a real host (no second Mac yet; nothing was run against the live Sill session on this Mac).

Later the same day: Sill Viewer's version is 0.6.3 (Packaging/Client-Info.plist still said #66's 0.5.1), and it has an icon of its own, `design/ViewerIcon.svg` (direction "Mac to Mac", chosen by David from four sketches: Sill's icon with a MacBook in front of the iMac). `Scripts/make-client-app.sh` compiles it as make-app.sh compiles Sill's, so the Viewer no longer takes its icon from a built Sill.app. Verified: after `xcodebuild -runFirstLaunch` (actool had failed with an Xcode plug-in error, as the iOS build did), the app carries Assets.car and AppIcon.icns, and Finder shows the icon masked into the macOS shape; the SVG's Quick Look render was checked at 1024 and 128 px.
