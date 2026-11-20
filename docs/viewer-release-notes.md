# Sill Viewer 0.6.3 (build 1720) — release notes

Sill Viewer shows the apps, windows and Desktops of another Mac on this Mac, each as a window of its
own, and lets you use them with this Mac's keyboard, mouse and trackpad. The other Mac runs Sill, as it
does for the iPhone and iPad. Free and open source (Apache-2.0); no account, no subscription, no
servers.

Build 1720, commit `bfc4031`, branch `mac-client-sync-upstream`. A test build: signed ad hoc, not
notarized (see Installing).

## Requirements

**This Mac (the one you sit at)**
- macOS 14 Sonoma or later.
- A Mac with Apple silicon. This build is arm64 only.
- The same network as the other Mac (Ethernet, Wi‑Fi, or a direct cable), or, away from home, a way
  to reach it (Tailscale or another VPN) and Remote Access turned on in Sill on the other Mac.

**The other Mac (the one whose apps you use)**
- Sill (the Mac app) running and signed in to the same network, from its first public build on. Sill
  Viewer needs nothing newer on that Mac for any feature in these notes.
- Sill's own permissions on that Mac, which it asks for at its first launch (Sill › Settings ›
  Permissions):
  - **Screen Recording** — to show its windows and Desktop. Takes effect after Sill relaunches.
  - **Accessibility** — to take your clicks and typing, and to resize a window to the size of its
    window here. Without it, windows keep their own size and the picture is scaled to fit.
  - **Audio recording** (once) — only if you turn sound on.
- The first time a window of it is shown here, macOS on that Mac may ask what to show on a display
  named "Sill": choose **Extended Display** and **Set as Default**. Sill keeps the windows you open
  here on that hidden display while they are shown, and puts them back when you close them.

## Permissions on this Mac

Sill Viewer asks for each only when a feature needs it. Everything else works without them.

| Permission | When it is asked | What it is for | Without it |
|---|---|---|---|
| **Local Network** | At first launch | Finding your other Macs on the network | No Mac is listed; Add a Mac by address still works |
| **Accessibility** | When you turn on Capture System Shortcuts (menu bar menu, or Capture shortcuts in the launcher) | ⌘Tab, ⌘Space and the other shortcuts macOS keeps for itself go to the other Mac | Those shortcuts stay on this Mac; every other key still goes across |
| **Paste from Other Apps** | The first time the other Mac's clipboard is shared | Sending what you copy here to the other Mac | Copies from the other Mac still arrive here; use **Allow Clipboard Access…** in the menu bar menu, which opens Privacy & Security › Paste from Other Apps, and set Sill Viewer to Allow |
| **Login item** | When you choose Launch at Login | Starting Sill Viewer when you log in, and reconnecting to the last Mac | Open it yourself |

Sill Viewer never asks for Screen Recording, the camera or the microphone on this Mac. Sound plays
through this Mac's output; recording happens on the other Mac.

The pairing key that identifies this Mac to the other is kept in the login keychain
(`me.saffer.sill.device-key`). On the other Mac, this Mac shows as a device in Sill › Settings ›
Devices, where it can be removed.

## What's new

### The launcher
One window for everything the other Mac offers, opened on connecting and by Sill Viewer's Dock icon.
- **A sidebar** with the Mac and its connection, Home, Favourites, All Apps, the other Mac's Desktops
  (one per display), its stream settings (Quality, Theme, Sound, Capture shortcuts) and Disconnect.
  Hide it with the sidebar button or **⌃⌘S**; while hidden, the settings are a row of icons at the top
  right and the Desktops join the open windows.
- **Open windows** as large pictures, an open one outlined.
- **Favourites**: right-click any app and choose **Add to Favourites** (or Remove). They sit on a shelf,
  each with its name, in the order you added them, and are kept for each Mac separately.
- **All Apps**, sorted **A–Z**, or **Recent**: only what you have opened from here (apps, and Desktops),
  latest first. Recent starts empty. A search always looks through every app.
- **Search** across apps, window titles and display names; Return opens the first match; Escape closes
  the launcher.
- **Three themes**: **Midnight** (deep blue and purple), **Graphite** (neutral dark grey) and
  **Daylight** (light and frosted). Choose from the Theme row in the sidebar, or the palette icon while
  it is hidden. The launcher's menus and controls follow the theme's light or dark look.
- A click on an app opens it even while the launcher is behind another app's window.

### Connecting
- **Welcome page**: when no Mac is connected, the window shows **Choose a Mac**, with a card for each Mac
  on the network or saved for away from home, saying how it is reached (Wired, Wi‑Fi, Direct, Remote,
  Not paired, Update Sill). Right-click a card for **Connect Remotely** or **Forget**. **Search Nearby**
  finds a Mac with Direct Wireless Connection on, without a network.
- **Mac switcher**: while connected, click the Mac's name at the top of the sidebar to switch to another
  Mac, add one, search nearby, or disconnect.
- **Add a Mac**, in the same window: type the 12-digit code a Not paired Mac shows; or, away from home,
  its address and code, or a `sill://pair` link (pasted, or opened from Messages).
- At launch Sill Viewer reconnects to the Mac it was last connected to, without a window in the way; the
  welcome page appears if that has not worked after 15 seconds. Disconnect forgets it.

### A locked Mac
- When the other Mac's screen is locked, its Sill sends no apps or windows until it is unlocked. The
  launcher now says so instead of looking empty: a picture of its lock screen (showing this Mac's time),
  "<Mac> is locked", and **Unlock Desktop**. A click anywhere on it opens the Desktop, where you type
  your password on the lock screen; the apps and windows come back by themselves.
- The sidebar's line reads **Screen locked** with an orange dot.

### The other Mac's display asleep
- Opening the Desktop or a window wakes the other Mac's display if it was asleep, as a key press there
  would. The wake is a pointer move sent only while nothing streams, which the other Mac then discards,
  so nothing moves or is clicked.

### The Dock and the app switcher
- Each of the other Mac's apps with a window open here has its own icon in the Dock and in **⌘Tab**, its
  own icon with Sill Viewer's in the corner. Click it or switch to it to bring that app's windows
  forward; its Dock menu lists them; Quit closes them here (the app goes on running on the other Mac).
- **The Desktop** has a Dock and switcher icon of its own, with its own picture. Kept in the Dock and
  clicked with no Desktop open, it opens the main display's Desktop.
- Switching to **Sill Viewer** itself (⌘Tab, or its Dock icon) brings up the launcher.

### Using the other Mac
- Each window of the other Mac is a window here, with a pill above the focused one for close, minimise
  and full screen. Resizing a window here resizes it on the other Mac (needs Accessibility there).
- The other Mac's app menus appear in this Mac's menu bar while one of its windows is in front.
- Keys go to the other Mac while its window has the keyboard, ⌘W and ⌘Q included. **⌃⌥⌘⎋** gives the
  keyboard back to this Mac.
- **Clipboard**: Share Clipboard in the menu bar menu.
- **Sound** (beta): **Send Audio** turns the other Mac's sound on for every device connected to it, as
  the iPhone's Settings panel does; it is off until turned on there or here. **Mute on This Mac**
  silences it here alone while the other Mac keeps sending. Both are in the launcher's settings (the
  speaker icon while the sidebar is hidden) and the menu bar menu. The sound is that of the window in
  front, or of every app while a Desktop is in front.
- **Files**: drop files on a window to give them to its app; drag files out of a window onto this Mac
  (the Trash too).
- **About Sill Viewer** shows the version, build number and commit.

## Known limitations
- **Resizing**: after a resize the picture can show black bars for up to about a second while the other
  Mac restarts its stream at the new size. Only the window in front is resized; a window in the
  background takes its new size when you click into it.
- Choosing a Sill Viewer window in Mission Control may bring up the launcher instead.
- A Desktop window shows the whole display scaled to fit; it does not change the other Mac's resolution.
- An app that keeps a fixed or minimum size, or a window in full screen, keeps its own size.
- The Dock icons are small helper apps Sill Viewer makes in
  `~/Library/Application Support/Sill Viewer/Dock` and signs ad hoc on this Mac; they quit when their
  app has no window here or when Sill Viewer quits. Turn them off with
  `defaults write me.saffer.sill.client SillClient.dockIcons -bool NO`.

## Installing this test build
1. Unzip `Sill Viewer 0.6.3 (1720) bfc4031.zip` and move **Sill Viewer** to Applications.
2. It is signed ad hoc, not notarized: the first time, Control-click it and choose **Open**, then Open
   again (or allow it in System Settings › Privacy & Security).
3. Allow **Local Network** when asked.
4. On the other Mac, make sure Sill is running with Screen Recording and Accessibility on.
5. In Sill Viewer, click the other Mac's card. If it says Not paired, type the code it shows.

Rolling back: every test build is kept as a zip in `~/SillViewerBuilds` and tagged
`viewer-<version>-b<build>`; install the previous zip.

## Troubleshooting
- **All Apps is empty and only the Desktop shows**: the other Mac is locked. Use Unlock Desktop.
- **The Desktop or a window stays black**: the other Mac's display may be asleep and slow to wake; open it
  again. If it never comes, check Screen Recording for Sill on the other Mac.
- **Windows don't resize**: turn on Accessibility for Sill on the other Mac. Its log says "Window sizing
  needs Accessibility permission" (`~/Library/Logs/Sill/Sill.log`).
- **Timing a slow window**: `defaults write me.saffer.sill.client SillTiming -bool YES`, relaunch, and
  read `~/Library/Logs/Sill Viewer/open-timing.log`. Turn it off with
  `defaults delete me.saffer.sill.client SillTiming`.
