# PRD: Sill for Mac (client) — "Sill Viewer"

Status: Draft 1 · 2026-11-09 · Owner: David Head
Source analysed: github.com/Saffsanity/sill @ `41e8cb8` (v0.6.1, Apache-2.0)

---

## 1. Summary

Sill today is a Mac **host** (menu-bar app, "Sill for Mac") plus an iPhone/iPad **client**. The host captures one
window (or the desktop) with ScreenCaptureKit, encodes HEVC, and streams it over TLS 1.3 to a paired device; input,
clipboard, menus and audio flow back. No account, no server.

There is **no client that runs on a Mac**. This PRD defines one: a macOS app that connects to a Sill host on another
Mac and shows that Mac's windows as windows on this Mac. Working name: **Sill Viewer**.

## 2. Findings that shape the plan (read first)

1. **The wire protocol is client-agnostic and already Mac-ready.** `Sources/StreamProtocol` (3.3k lines, SwiftPM
   library, `.macOS(.v14)` + `.iOS(.v17)`) is shared by host and iOS client. A Mac client needs no host rewrite to *connect, pair, stream, type, click*.
2. **The iOS client is ~31k lines, 18 of 54 files import UIKit.** The session core (`StreamClient*.swift`, ~7.8k lines,
   pairing, remote connector, saved Macs, device identity) is reusable; the display view, input views, overlays and the settings panel are not.
3. **Upstream already has this work, unmerged.** Open PRs from outside contributors:
   - **#66** (ashleigh-hopkins, +10.7k lines): full "Sill Viewer" in `Sources/MacClient`, per-window native windows, menus in menu bar, Dock proxies, clipboard, audio, file drag-and-drop, system-shortcut tap, plus host changes (side streams, desk stages). Stacked with #72, #73.
   - **#128** (Aileuxe): a second "Sill Viewer" (Xcode target, `#if os(macOS)` shims) bundled with Rust hosts for Windows/Linux.
   - Maintainer (Noah) said on 2026-10-19 that **at most one design can land** and the name needs settling; no decision yet. Related: issue #129 "Mac to Mac support?", #158 (visionOS), #207 (Windows client).
4. **Both PRs are stale against main** (kind-number collisions with audio=43 and keyframe=44, clipboard shape from #78, keyframe recovery from #93 not in the Mac display view). Rebasing is real work, not a formality.
5. **Project rules constrain us:** Swift + Apple frameworks only, no third-party deps, nothing needing a server, latency before picture quality, checks/mutant tests required (`Tests/checks/run-all.sh`). The Mac host is Developer ID, not Mac App Store (private virtual-display API + Accessibility).
6. **Competition for Mac→Mac is weak at the per-window level:** built-in Screen Sharing is whole-desktop only (confirmed by users on #129); Parsec/Jump/Screens are whole-desktop and paid or account-based. Sill's per-window, free, serverless angle carries over.
7. **`davidjhead/sill` does not exist yet.** The repo must be created (fork of `Saffsanity/sill`) before anything can be pushed.

## 3. Strategic decision needed before build

| Option | What it means | Pros | Cons |
|---|---|---|---|
| **A. Fork + adopt #66** (recommended) | Fork, rebase #66 (+#72/#73) onto current main, finish, ship from your repo, optionally re-offer upstream | ~10k lines of working, hand-verified behaviour (windows, menus, clipboard, files, Dock). Biggest feature set. Swift-only, within rules | Large rebase; host-side changes (desk stages, side streams) widen the diff and risk to the host; depends on author's code quality and licence terms (Apache-2.0 okay) |
| B. Fork + adopt #128's viewer only | Take the Xcode-target viewer, drop Rust hosts | Smaller viewer surface; reuses iOS client via shims | Less featureful; shim approach conflicts with upstream's later iOS changes; second-best on maintainer's own comparison |
| C. Greenfield on `StreamProtocol` | New macOS target, write the client from scratch against the shared protocol | Cleanest architecture; you own every line; minimal host change | Re-solves problems #66 already solved; slowest to parity |

**Recommendation: A, executed as a staged merge** — land the client first (MVP), then the host-side extras (side streams, file drag, Dock) as separate PRs. Verify code and authorship rights before copying (see §9).

## 4. Goals and non-goals

**Goals**
- A Mac can connect to a paired Sill host Mac and use any single window, or the whole desktop, as a native window.
- Parity with the iOS client's trust model: pairing, TLS pinning, same-LAN, USB, direct wireless, remote access.
- Feels like a Mac app: real window chrome, menu bar, Dock, trackpad scrolling, hardware keyboard, shortcuts.
- Free, no account, no server, Apache-2.0, built only from Apple frameworks.

**Non-goals (v1)**
- Windows/Linux hosts (Rust, #128): out of scope.
- Mac App Store distribution (host constraint does not apply to a client, but notarised Developer ID ships first).
- Multi-user / sharing to many viewers, file-sync, or any cloud relay.
- Replacing macOS Screen Sharing for headless admin use.

## 5. Users and use cases

1. **Two-Mac owner:** laptop on the couch reaching the Mac mini / studio Mac's apps (Xcode, Logic, a render queue) as windows.
2. **Mac laptop + home server:** keep one app (Photos, Mail) alive on an always-on Mac.
3. **Away from home:** same, through Tailscale / port-forward Remote Access.
4. **Developer/tester:** drive a second Mac (CI box, older macOS) for testing.

## 6. Requirements and priorities

Priority key: **P0** = MVP (cannot ship without), **P1** = v1.0, **P2** = after 1.0, **P3** = exploratory.
Effort: S ≤ 3 days · M ≈ 1–2 weeks · L ≈ 3+ weeks (solo estimates, rough).

### P0 — MVP: "I can use a remote window"
| # | Requirement | Notes | Effort |
|---|---|---|---|
| 0.1 | Repo foundation: fork to `davidjhead/sill`, CI green on a macOS client target, build script (`make-client-app.sh`) | Follow CLAUDE.md conventions; run-all.sh must pass | S |
| 0.2 | Platform layer so the iOS `StreamClient` session core compiles on macOS (or move to a shared SwiftPM target) | Biggest architectural choice; resolve UIKit coupling in 18 files; keep iOS app unchanged | L |
| 0.3 | Discovery (Bonjour) + saved Macs + device list window | Reuse `DiscoveryPolicy`, `SavedMacs` | M |
| 0.4 | Pairing: enter/scan 12-digit code, Wired auto-pair, TLS pinned reconnect | Mac has no camera scan requirement: typed code only at first | M |
| 0.5 | HEVC decode + display in an `NSWindow` (AVSampleBufferDisplayLayer), with keyframe recovery (kind 44) | Must include recovery added after #66 forked | M |
| 0.6 | Window switcher: pick window / app / Desktop from the host catalog | Native sidebar or menu | M |
| 0.7 | Input: pointer, buttons, scroll with momentum/phases, keys by position, text | Reuse protocol `InputEvent`; Mac key map | L |
| 0.8 | Viewport/sizing: tell host the panel size and scale so text is crisp (Retina) | `Viewport.swift` | M |
| 0.9 | Notarised, signed build + DMG, permission/onboarding (Local Network) | Client needs fewer TCC permissions than host | S |

### P1 — v1.0: "feels like a Mac app"
| # | Requirement | Effort |
|---|---|---|
| 1.1 | Remote app menus in the Mac menu bar (kinds 24/25/27) | M |
| 1.2 | Clipboard both ways, text first, images next; loop guard when two Macs view each other (kind 32) | M |
| 1.3 | Audio playback of the host's sound (kind 43, AAC-ELD), mute toggle | M |
| 1.4 | Remote Access / away-from-home connection (reuse `RemoteConnector`) | M |
| 1.5 | Link-quality UX: "can't keep up" notice, quality/resolution controls (HostSettings kinds 16/17) | S |
| 1.6 | Remote cursor shape and the host pointer overlay (kinds 14, 26) | S |
| 1.7 | Gestures and system shortcuts: Mission Control, Spaces; optional event tap for ⌘Tab etc. | M |
| 1.8 | Window commands: close / minimise / full-screen (kind 15) as Mac window controls | S |
| 1.9 | Auto-reconnect after sleep/loss; reopen last session on launch | M |
| 1.10 | Loop protection: client never sends input the local host injected; host never lists the viewer's own windows | S |
| 1.11 | Check suite: protocol, key-map and router checks with mutants, per upstream convention | M |

### P2 — after 1.0
| # | Requirement | Effort |
|---|---|---|
| 2.1 | Multiple windows open at once, one per remote window (needs host side streams: kinds 29–31) | L |
| 2.2 | One Mac window per host display for Desktop mode (issue #91) | M |
| 2.3 | File drag-and-drop in/out (host kinds 34–38) | L |
| 2.4 | Dock integration: per-app Dock icons, badges, Dock menus (`DockProxies`, `SillDockProxy`) | L |
| 2.5 | Several hosts connected at once, one window group each | M |
| 2.6 | Homebrew cask, auto-update check, release automation | S |
| 2.7 | Accessibility pass: VoiceOver on controls, Large Text, Full Keyboard Access | M |

### P3 — exploratory
- Notifications/Dock bounce forwarding (no public macOS API; upstream spiked it).
- Stage Manager / Spaces awareness of remote windows.
- Microphone/camera passthrough (issue #214 for iPad).
- Upstream the work: split into reviewable PRs for Saffsanity/sill.

## 7. Architecture sketch

- **Targets:** `SillViewer` (macOS app, AppKit lifecycle + SwiftUI panes), reusing `StreamProtocol` unchanged and a new shared SwiftPM target `SillClientCore` holding the session logic extracted from `iOSClient/StreamClient*.swift`, `SessionLink`, `RemoteConnector`, `SavedMacs`.
- **Platform seams** (as in #66): `ClientPlatform`, `HEVCSampleFeed`, display view, input view; each has an iOS and a macOS implementation.
- **Decode/display:** VideoToolbox + `AVSampleBufferDisplayLayer`, as iOS.
- **Host side for MVP:** none. P2 items (side streams, desk stages, files) are additive and gated by capability flags in the window list, so the compatibility floor stays unchanged.
- **Security:** keep pinned-key pairing, TLS 1.3, Keychain identity; the Mac viewer's identity lives in the data-protection keychain under its own signing identity.

## 8. Success metrics

- Pairing to first picture < 2 min (project goal), < 30 s on an already-paired Mac.
- LAN glass-to-glass latency ≈ iOS client (≈ 40–60 ms estimated by upstream); no regression on host.
- 1-hour session without drop or forced reconnect on LAN.
- 0 crashes in the first 20 hours of dogfooding across two Macs (Apple silicon + Intel host).
- `Tests/checks/run-all.sh` green on CI.

## 9. Risks and open questions

| Risk / question | Mitigation / owner |
|---|---|
| Rebasing #66 is large; host changes in the same PR add risk to the shipping host | Split host-side changes out; land client MVP against an unmodified host first |
| Code rights: #66/#128 are third-party contributions (Apache-2.0 via project licence terms) | Confirm contribution terms, keep authors' attribution and history (preserve commits, don't squash away authorship); ask ashleigh-hopkins |
| Upstream may merge a *different* viewer, forking you from main | Keep client in its own target and directory; track upstream weekly |
| Naming clash ("Sill Viewer" used by both PRs; trademark/branding of "Sill") | Decide name with Noah, or use a distinct name for your build |
| Private macOS APIs on the host (virtual display) can break per macOS release | Out of client scope; host already falls back |
| Two Macs viewing each other: input and clipboard loops | Requirement 1.10 and 1.2 |
| Firewall stalls on macOS 27.3 (issue #314), off-console session refusal (#316) | Test matrix; surface clear errors |

**Open questions for you**
1. Option A, B or C (§3)?
2. Ship as a **separate app** from your fork only, or also try to **upstream** to Saffsanity/sill?
3. Do you want **Intel host + Apple silicon client** testing as MVP gates?
4. Target macOS floor for the client: 14 (matches host) or 15+?

## 10. Proposed phases

| Phase | Scope | Exit criteria |
|---|---|---|
| 0 Setup (≈ 1 wk) | Fork, CI, spike: does `StreamClient` compile for macOS with shims; pick A/B/C | Decision recorded; main builds on your fork |
| 1 MVP (≈ 4–6 wks) | All P0 | Two real Macs: pair, pick a window, click, type, scroll, reconnect |
| 2 v1.0 (≈ 4–6 wks) | All P1 | Dogfood week, notarised DMG, README + site copy |
| 3 Post-1.0 | P2 by demand | Per item |
